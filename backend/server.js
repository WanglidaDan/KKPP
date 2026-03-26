const express = require("express");
const cors = require("cors");
const dotenv = require("dotenv");
const OpenAI = require("openai");
const { toFile } = require("openai/uploads");

dotenv.config();

const app = express();
const port = Number(process.env.PORT || 3000);
const defaultTimezone = process.env.TIMEZONE || "Asia/Shanghai";
const memoryWindow = Number(process.env.MEMORY_WINDOW || 12);
const defaultModel = process.env.DEFAULT_MODEL || "qwen-plus";
const complexModel = process.env.COMPLEX_MODEL || "qwen-max";
const transcriptionModel = process.env.TRANSCRIPTION_MODEL || "gpt-4o-mini-transcribe";
const transcriptionBaseURL = process.env.TRANSCRIPTION_BASE_URL || process.env.OPENAI_BASE_URL;
const transcriptionApiKey = process.env.TRANSCRIPTION_API_KEY || process.env.OPENAI_API_KEY || "";
const modelRequestTimeoutMs = Number(process.env.MODEL_REQUEST_TIMEOUT_MS || 45000);
const allowedOrigins = String(process.env.CORS_ORIGINS || "")
  .split(",")
  .map((item) => item.trim())
  .filter(Boolean);

if (!process.env.DASHSCOPE_API_KEY) {
  console.warn("Missing DASHSCOPE_API_KEY. Create a .env file before running the server.");
}

const client = new OpenAI({
  apiKey: process.env.DASHSCOPE_API_KEY,
  baseURL: process.env.DASHSCOPE_BASE_URL || "https://dashscope.aliyuncs.com/compatible-mode/v1"
});

const transcriptionClient = transcriptionApiKey
  ? new OpenAI({
      apiKey: transcriptionApiKey,
      baseURL: transcriptionBaseURL || undefined
    })
  : null;

const conversationStore = new Map();

app.set("trust proxy", 1);
app.use(cors({
  origin(origin, callback) {
    if (!origin || allowedOrigins.length === 0 || allowedOrigins.includes(origin)) {
      return callback(null, true);
    }

    return callback(new Error("CORS origin not allowed"));
  }
}));
app.use(express.json({ limit: "1mb" }));

function chooseModel(text) {
  const complexSignals = [
    "改期",
    "重新安排",
    "如果",
    "同时",
    "衝突",
    "冲突",
    "总结",
    "本周",
    "下周",
    "整理",
    "project",
    "schedule",
    "reschedule"
  ];

  const normalizedText = String(text || "").toLowerCase();
  const isComplex = normalizedText.length > 90 || complexSignals.some((signal) => normalizedText.includes(signal.toLowerCase()));
  return isComplex ? complexModel : defaultModel;
}

function getConversation(userId) {
  if (!conversationStore.has(userId)) {
    conversationStore.set(userId, []);
  }

  return conversationStore.get(userId);
}

function saveMessage(userId, role, content) {
  const history = getConversation(userId);
  history.push({ role, content });

  if (history.length > memoryWindow) {
    history.splice(0, history.length - memoryWindow);
  }
}

function serializeCalendarContext(calendarContext) {
  const events = Array.isArray(calendarContext?.events) ? calendarContext.events : [];
  if (events.length === 0) {
    return "No local calendar context provided.";
  }

  return JSON.stringify(
    events.map((event) => ({
      title: event.title || "",
      startISO: event.startISO || "",
      endISO: event.endISO || "",
      location: event.location || ""
    }))
  );
}

function getSharedContext({ userId, text, timezone, calendarContext, deviceContext }) {
  const now = new Date().toISOString();
  const history = getConversation(userId).slice(-memoryWindow);
  const currentReferenceTimeISO = deviceContext?.currentDateISO || now;

  return {
    timezone,
    currentServerTimeISO: now,
    currentReferenceTimeISO,
    userText: text,
    recentConversation: history,
    deviceContext: deviceContext || null,
    calendarContext: Array.isArray(calendarContext?.events) ? calendarContext.events : []
  };
}

function buildStageMessages(stagePrompt, sharedContext) {
  return [
    {
      role: "system",
      content: stagePrompt.trim()
    },
    {
      role: "user",
      content: JSON.stringify(sharedContext)
    }
  ];
}

function buildChatCompletionOptions({ model, temperature, messages, responseFormat = null, stream = false }) {
  const options = {
    model,
    temperature,
    messages,
    timeout: modelRequestTimeoutMs
  };

  if (responseFormat) {
    options.response_format = responseFormat;
  }

  if (stream) {
    options.stream = true;
  }

  if (String(model).startsWith("qwen3")) {
    options.enable_thinking = false;
  }

  return options;
}

function safeParseJSON(rawText, fallback = {}) {
  if (!rawText) {
    return fallback;
  }

  try {
    return JSON.parse(rawText);
  } catch {
    const jsonMatch = String(rawText).match(/\{[\s\S]*\}/);
    if (!jsonMatch) {
      return fallback;
    }

    try {
      return JSON.parse(jsonMatch[0]);
    } catch {
      return fallback;
    }
  }
}

async function runJSONStage({ model, stagePrompt, sharedContext, temperature = 0.1 }) {
  const completion = await client.chat.completions.create(
    buildChatCompletionOptions({
      model,
      temperature,
      messages: buildStageMessages(stagePrompt, sharedContext),
      responseFormat: { type: "json_object" }
    })
  );

  return safeParseJSON(completion.choices[0]?.message?.content, {});
}

async function runCollaborativeStage({ model, sharedContext }) {
  const completion = await client.chat.completions.create(
    buildChatCompletionOptions({
      model,
      temperature: 0.1,
      messages: buildStageMessages(getCollaborativePipelinePrompt(), sharedContext),
      responseFormat: { type: "json_object" }
    })
  );

  return safeParseJSON(completion.choices[0]?.message?.content, {});
}

function getIntentAnalysisPrompt() {
  return `
You are the Intent Analyst for KKPP, an executive calendar assistant.
Analyze the request and return strict JSON only.

Required JSON shape:
{
  "userGoal": "short summary",
  "intentType": "add_event | query_schedule | modify_existing | delete_existing | other",
  "complexity": "low | medium | high",
  "needsClarification": true,
  "clarificationQuestion": "one concise Simplified Chinese question or empty string",
  "shouldUseTool": true,
  "reasoningSummary": "very short internal summary",
  "confidence": 0.0
}

Rules:
- Reply with JSON only.
- Treat relative time using currentReferenceTimeISO and timezone.
- Prefer deviceContext.currentDateISO and deviceContext.localDateLabel when present.
- If the user wants to modify or delete existing events, mark the intent accordingly.
- If essential details are missing and cannot be safely inferred, set needsClarification to true.
- KKPP currently supports only adding and querying schedule actions.
`.trim();
}

function getPlanningPrompt() {
  return `
You are the Scheduler Planner for KKPP.
Turn the analyzed request into a concrete scheduling plan and return JSON only.

Required JSON shape:
{
  "proposedActionType": "add_calendar_event | query_calendar_events | clarify | reply_only",
  "title": "",
  "startISO": "",
  "durationHours": 1,
  "notes": "",
  "location": "",
  "reminderMinutesBefore": 15,
  "dateISO": "",
  "rangeDays": 1,
  "focus": "",
  "assumptions": [""],
  "missingFields": [""],
  "planningSummary": "brief internal summary"
}

Rules:
- Reply with JSON only.
- Treat relative time using currentReferenceTimeISO and timezone.
- Prefer deviceContext.currentDateISO and deviceContext.localDateLabel when present.
- For add_calendar_event, fill title/startISO/durationHours/notes/location/reminderMinutesBefore.
- For query_calendar_events, fill dateISO/rangeDays/focus.
- If a reasonable assumption is safe, make it and record it in assumptions.
- If details are essential and missing, list them in missingFields and use proposedActionType = clarify.
- This version does not support modifying or deleting existing events; use clarify or reply_only for those cases.
`.trim();
}

function getDecisionPrompt() {
  return `
You are the Action Decider for KKPP.
Based on the shared context, intent analysis, and planner output, decide the next action.
Return JSON only.

Required JSON shape:
{
  "decision": "call_tool | clarify | reply_only",
  "toolName": "add_calendar_event | query_calendar_events |",
  "toolArguments": {},
  "toolCalls": [
    {
      "toolName": "add_calendar_event | query_calendar_events",
      "toolArguments": {}
    }
  ],
  "internalSummary": "brief internal summary",
  "userFacingInstruction": "short instruction for the secretary responder"
}

Rules:
- Reply with JSON only.
- Treat relative time using currentReferenceTimeISO and timezone.
- Prefer deviceContext.currentDateISO and deviceContext.localDateLabel when present.
- call_tool only when the plan is safe and sufficiently complete.
- clarify when essential information is missing.
- reply_only when no tool is needed or the request is unsupported in the current version.
- Supported tools are only add_calendar_event and query_calendar_events.
`.trim();
}

function getCollaborativePipelinePrompt() {
  return `
You are KKPP's synchronous specialist board.
Simulate these specialists working together in one pass:
1. Intent Analyst
2. Scheduler Planner
3. Action Decider

Return strict JSON only in this exact shape:
{
  "intentAnalysis": {
    "userGoal": "short summary",
    "intentType": "add_event | query_schedule | modify_existing | delete_existing | other",
    "complexity": "low | medium | high",
    "needsClarification": true,
    "clarificationQuestion": "one concise Simplified Chinese question or empty string",
    "shouldUseTool": true,
    "reasoningSummary": "very short internal summary",
    "confidence": 0.0
  },
  "planning": {
    "proposedActionType": "add_calendar_event | query_calendar_events | clarify | reply_only",
    "title": "",
    "startISO": "",
    "durationHours": 1,
    "notes": "",
    "location": "",
    "reminderMinutesBefore": 15,
    "dateISO": "",
    "rangeDays": 1,
    "focus": "",
    "assumptions": [""],
    "missingFields": [""],
    "planningSummary": "brief internal summary"
  },
  "decision": {
    "decision": "call_tool | clarify | reply_only",
    "toolName": "add_calendar_event | query_calendar_events |",
    "toolArguments": {},
    "toolCalls": [
      {
        "toolName": "add_calendar_event | query_calendar_events",
        "toolArguments": {}
      }
    ],
    "internalSummary": "brief internal summary",
    "userFacingInstruction": "short instruction for the secretary responder"
  }
}

Rules:
- Reply with JSON only.
- Treat relative time using currentReferenceTimeISO and timezone.
- Prefer deviceContext.currentDateISO and deviceContext.localDateLabel when present.
- Supported tools are only add_calendar_event and query_calendar_events.
- For multiple concrete tasks in one sentence, prefer returning multiple toolCalls in the original user order.
- If the user wants to modify or delete existing events, do not invent support. Use clarify or reply_only.
- Make reasonable assumptions when safe, and record them in assumptions.
`.trim();
}

function getResponderPrompt() {
  return `
You are the Secretary Responder for KKPP.
Write the final user-facing reply in Simplified Chinese.

Rules:
- Tone: warm, concise, polished, professional private secretary.
- Confirm the action clearly.
- Mention assumptions only when useful.
- Ask at most one clarification question if needed.
- If the request is unsupported, explain that the current version supports adding and querying schedules.
- Return plain text only.
`.trim();
}

function normalizeStructuredAction(toolName, args = {}) {
  if (!toolName) {
    return null;
  }

  if (toolName === "add_calendar_event") {
    return {
      type: "add_calendar_event",
      payload: {
        title: String(args.title || ""),
        startISO: String(args.startISO || ""),
        durationHours: Number(args.durationHours || 1),
        notes: String(args.notes || ""),
        location: String(args.location || ""),
        reminderMinutesBefore: Number(args.reminderMinutesBefore || 15)
      }
    };
  }

  if (toolName === "query_calendar_events") {
    return {
      type: "query_calendar_events",
      payload: {
        dateISO: String(args.dateISO || ""),
        rangeDays: Number(args.rangeDays || 1),
        focus: String(args.focus || "")
      }
    };
  }

  return null;
}

function normalizeStructuredActionsFromDecision(decisionResult) {
  if (decisionResult?.decision !== "call_tool") {
    return [];
  }

  const toolCalls = Array.isArray(decisionResult?.toolCalls) && decisionResult.toolCalls.length > 0
    ? decisionResult.toolCalls
    : [{
        toolName: decisionResult?.toolName,
        toolArguments: decisionResult?.toolArguments || {}
      }];

  return toolCalls
    .map((call) => normalizeStructuredAction(call?.toolName, call?.toolArguments || {}))
    .filter(Boolean);
}

function buildToolResult(structuredActions, calendarContext) {
  if (!Array.isArray(structuredActions) || structuredActions.length === 0) {
    return "No tool action was selected.";
  }

  return JSON.stringify(structuredActions.map((structuredAction) => {
    if (structuredAction.type === "add_calendar_event") {
      return {
        status: "planned",
        type: structuredAction.type,
        event: structuredAction.payload,
        instruction: "The iOS client should add this event through EventKit."
      };
    }

    if (structuredAction.type === "query_calendar_events") {
      return {
        status: "planned",
        type: structuredAction.type,
        query: structuredAction.payload,
        localEvents: Array.isArray(calendarContext?.events) ? calendarContext.events : [],
        instruction: "The iOS client should use EventKit data to fulfill the query."
      };
    }

    return {
      status: "unsupported",
      type: structuredAction.type
    };
  }));
}

async function runCollaborativePipeline({ userId, text, timezone, calendarContext, deviceContext }) {
  const model = chooseModel(text);
  const sharedContext = getSharedContext({ userId, text, timezone, calendarContext, deviceContext });
  const stageModel = defaultModel;
  const collaborativeResult = await runCollaborativeStage({
    model: stageModel,
    sharedContext
  });

  const intentAnalysis = collaborativeResult.intentAnalysis || {};
  const planning = collaborativeResult.planning || {};
  const decision = collaborativeResult.decision || {};

  const structuredActions = normalizeStructuredActionsFromDecision(decision);
  const structuredAction = structuredActions[0] || null;

  return {
    model,
    stageModel,
    sharedContext,
    intentAnalysis,
    planning,
    decision,
    structuredAction,
    structuredActions
  };
}

async function generateFinalReply({ model, sharedContext, intentAnalysis, planning, decision, structuredAction, structuredActions, calendarContext }) {
  const responderInput = {
    sharedContext,
    intentAnalysis,
    planning,
    decision,
    structuredAction,
    structuredActions,
    toolResult: structuredActions?.length ? buildToolResult(structuredActions, calendarContext) : null
  };

  const completion = await client.chat.completions.create({
    ...buildChatCompletionOptions({
      model,
      temperature: 0.35,
      messages: [
        {
          role: "system",
          content: getResponderPrompt()
        },
        {
          role: "user",
          content: JSON.stringify(responderInput)
        }
      ]
    })
  });

  return completion.choices[0]?.message?.content || "我已为你整理好安排。";
}

async function streamFinalReply({ res, model, sharedContext, intentAnalysis, planning, decision, structuredAction, structuredActions, calendarContext }) {
  const responderInput = {
    sharedContext,
    intentAnalysis,
    planning,
    decision,
    structuredAction,
    structuredActions,
    toolResult: structuredActions?.length ? buildToolResult(structuredActions, calendarContext) : null
  };

  const stream = await client.chat.completions.create(
    buildChatCompletionOptions({
      model,
      temperature: 0.35,
      stream: true,
      messages: [
        {
          role: "system",
          content: getResponderPrompt()
        },
        {
          role: "user",
          content: JSON.stringify(responderInput)
        }
      ]
    })
  );

  let finalReply = "";

  for await (const chunk of stream) {
    const delta = chunk.choices?.[0]?.delta?.content || "";
    if (!delta) {
      continue;
    }

    finalReply += delta;
    res.write(`data: ${JSON.stringify({ type: "token", content: delta })}\n\n`);
  }

  return finalReply || "我已为你整理好安排。";
}

function validateBody(body) {
  if (!body?.userId || !body?.text) {
    return "userId and text are required";
  }

  return null;
}

function decodeFallbackText(rawValue) {
  if (!rawValue) {
    return "";
  }

  try {
    return Buffer.from(rawValue, "base64").toString("utf8");
  } catch {
    return "";
  }
}

function normalizeTranscriptionLanguage(localeIdentifier) {
  const value = String(localeIdentifier || "").toLowerCase();
  if (value.startsWith("zh")) {
    return "zh";
  }
  if (value.startsWith("en")) {
    return "en";
  }
  return undefined;
}

function buildTranscriptionPrompt(fallbackText) {
  const domainTerms = [
    "日程",
    "提醒",
    "会议",
    "客户",
    "改时间",
    "改地点",
    "拍摄",
    "航拍",
    "纪录片摄像",
    "视频拍摄",
    "飞书会议",
    "腾讯会议"
  ];

  const hint = fallbackText ? ` Possible rough realtime transcript: ${fallbackText}` : "";
  return `Transcribe the audio into concise Simplified Chinese. Preserve business scheduling terms and Chinese time expressions.${hint} Domain terms: ${domainTerms.join(", ")}`;
}

app.get("/health", (_req, res) => {
  res.json({
    ok: true,
    service: "kkpp-backend",
    timezone: defaultTimezone,
    timestamp: new Date().toISOString(),
    transcriptionAvailable: Boolean(transcriptionClient),
    collaborationMode: "synchronous-specialists",
    specialists: [
      "Intent Analyst",
      "Scheduler Planner",
      "Action Decider",
      "Secretary Responder"
    ]
  });
});

app.post("/transcribe", express.raw({ type: ["audio/*", "application/octet-stream"], limit: "20mb" }), async (req, res) => {
  if (!transcriptionClient) {
    return res.status(501).json({
      error: "High-accuracy transcription is not configured",
      details: "Set TRANSCRIPTION_API_KEY or OPENAI_API_KEY on the backend to enable this endpoint."
    });
  }

  if (!Buffer.isBuffer(req.body) || req.body.length === 0) {
    return res.status(400).json({ error: "Audio payload is required" });
  }

  const fileName = req.get("X-File-Name") || `kkpp-voice-${Date.now()}.wav`;
  const localeIdentifier = req.get("X-Locale-Identifier") || "zh-Hans";
  const fallbackText = decodeFallbackText(req.get("X-Fallback-Text-Base64"));

  try {
    const file = await toFile(req.body, fileName, { type: req.get("Content-Type") || "audio/wav" });
    const transcription = await transcriptionClient.audio.transcriptions.create({
      file,
      model: transcriptionModel,
      language: normalizeTranscriptionLanguage(localeIdentifier),
      prompt: buildTranscriptionPrompt(fallbackText),
      timeout: modelRequestTimeoutMs
    });

    return res.json({
      text: String(transcription.text || fallbackText || "").trim(),
      provider: transcriptionBaseURL || "openai",
      model: transcriptionModel
    });
  } catch (error) {
    console.error("Transcription error:", error);
    return res.status(500).json({
      error: "Failed to transcribe audio",
      details: error.message
    });
  }
});

app.post("/process", async (req, res) => {
  const validationError = validateBody(req.body);
  if (validationError) {
    return res.status(400).json({ error: validationError });
  }

  const {
    userId,
    text,
    timezone = defaultTimezone,
    calendarContext = {},
    deviceContext = null
  } = req.body;

  try {
    const pipeline = await runCollaborativePipeline({ userId, text, timezone, calendarContext, deviceContext });
    const reply = await generateFinalReply({
      ...pipeline,
      calendarContext
    });

    saveMessage(userId, "user", text);
    saveMessage(userId, "assistant", reply);

    return res.json({
      reply,
      structuredAction: pipeline.structuredAction,
      structuredActions: pipeline.structuredActions,
      collaboration: {
        intentAnalysis: pipeline.intentAnalysis,
        planning: pipeline.planning,
        decision: pipeline.decision
      }
    });
  } catch (error) {
    console.error("Process error:", error);
    return res.status(500).json({
      error: "Failed to process request",
      details: error.message
    });
  }
});

app.post("/process/stream", async (req, res) => {
  const validationError = validateBody(req.body);
  if (validationError) {
    return res.status(400).json({ error: validationError });
  }

  const {
    userId,
    text,
    timezone = defaultTimezone,
    calendarContext = {},
    deviceContext = null
  } = req.body;

  res.setHeader("Content-Type", "text/event-stream; charset=utf-8");
  res.setHeader("Cache-Control", "no-cache, no-transform");
  res.setHeader("Connection", "keep-alive");
  res.flushHeaders?.();

  try {
    res.write(`data: ${JSON.stringify({ type: "stage", stage: "bootstrap", message: "连接后端" })}\n\n`);
    const pipeline = await runCollaborativePipeline({ userId, text, timezone, calendarContext, deviceContext });

    const stageMessages = [
      pipeline.intentAnalysis?.reasoningSummary || pipeline.intentAnalysis?.userGoal || "理解用户意图",
      pipeline.planning?.planningSummary || "拆解日历任务",
      pipeline.decision?.internalSummary || "准备执行动作"
    ].filter(Boolean);

    const stageNames = ["intent", "planning", "decision"];
    stageMessages.forEach((message, index) => {
      res.write(`data: ${JSON.stringify({
        type: "stage",
        stage: stageNames[index],
        message
      })}\n\n`);
    });

    res.write(`data: ${JSON.stringify({
      type: "action",
      structuredAction: pipeline.structuredAction,
      structuredActions: pipeline.structuredActions,
      collaboration: {
        intentAnalysis: pipeline.intentAnalysis,
        planning: pipeline.planning,
        decision: pipeline.decision
      }
    })}\n\n`);

    const reply = await streamFinalReply({
      res,
      ...pipeline,
      calendarContext
    });

    saveMessage(userId, "user", text);
    saveMessage(userId, "assistant", reply);

    res.write(`data: ${JSON.stringify({
      type: "done",
      reply,
      structuredAction: pipeline.structuredAction,
      structuredActions: pipeline.structuredActions,
      collaboration: {
        intentAnalysis: pipeline.intentAnalysis,
        planning: pipeline.planning,
        decision: pipeline.decision
      }
    })}\n\n`);
    return res.end();
  } catch (error) {
    console.error("Stream error:", error);
    res.write(`data: ${JSON.stringify({ type: "error", message: error.message || "Unknown error" })}\n\n`);
    return res.end();
  }
});

app.listen(port, () => {
  console.log(`KKPP backend listening on http://localhost:${port}`);
});
