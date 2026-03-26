const express = require("express");
const cors = require("cors");
const dotenv = require("dotenv");
const OpenAI = require("openai");

dotenv.config();

const app = express();
const port = Number(process.env.PORT || 3000);
const defaultTimezone = process.env.TIMEZONE || "Asia/Shanghai";
const memoryWindow = Number(process.env.MEMORY_WINDOW || 12);
const defaultModel = process.env.DEFAULT_MODEL || "qwen-plus";
const complexModel = process.env.COMPLEX_MODEL || "qwen-max";

if (!process.env.DASHSCOPE_API_KEY) {
  console.warn("Missing DASHSCOPE_API_KEY. Create a .env file before running the server.");
}

const client = new OpenAI({
  apiKey: process.env.DASHSCOPE_API_KEY,
  baseURL: process.env.DASHSCOPE_BASE_URL || "https://dashscope.aliyuncs.com/compatible-mode/v1"
});

const conversationStore = new Map();

app.use(cors());
app.use(express.json({ limit: "1mb" }));

const calendarTools = [
  {
    type: "function",
    function: {
      name: "add_calendar_event",
      description: "Create a calendar event when the user clearly wants to add or schedule a new event.",
      parameters: {
        type: "object",
        properties: {
          title: {
            type: "string",
            description: "Short business-friendly title in Simplified Chinese when appropriate."
          },
          startISO: {
            type: "string",
            description: "Event start time in ISO 8601 format with timezone offset."
          },
          durationHours: {
            type: "number",
            description: "Event duration in hours."
          },
          notes: {
            type: "string",
            description: "Short agenda or helpful notes."
          },
          location: {
            type: "string",
            description: "Meeting venue or address."
          },
          reminderMinutesBefore: {
            type: "integer",
            description: "Reminder lead time in minutes."
          }
        },
        required: ["title", "startISO", "durationHours", "notes", "location"]
      }
    }
  },
  {
    type: "function",
    function: {
      name: "query_calendar_events",
      description: "Query schedule details when the user asks what is on the calendar.",
      parameters: {
        type: "object",
        properties: {
          dateISO: {
            type: "string",
            description: "Anchor date for the query in ISO 8601 format."
          },
          rangeDays: {
            type: "integer",
            description: "Query range in days."
          },
          focus: {
            type: "string",
            description: "User's focus, for example today's meetings or next three days."
          }
        },
        required: ["dateISO", "rangeDays", "focus"]
      }
    }
  }
];

function chooseModel(text) {
  const complexSignals = [
    "改期",
    "重新安排",
    "如果",
    "同時",
    "衝突",
    "總結",
    "本週",
    "下週",
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

function getSystemPrompt(timezone) {
  const now = new Date();
  return `
You are KKPP's multi-agent executive calendar assistant.

Internally you behave like four fast specialists:
1. Intent Analyst: understand the user's real goal.
2. Scheduler Planner: extract title, time, duration, location, reminders, and any reasonable assumptions.
3. Action Decider: decide whether to call a tool.
4. Secretary Responder: answer like a polished, warm, professional private secretary.

Rules:
- Reply to the user in Simplified Chinese.
- Keep the tone warm, concise, professional, and efficient.
- The active timezone is ${timezone}.
- Current server time is ${now.toISOString()}.
- Treat relative dates such as today, tomorrow, this afternoon, and next week relative to the current server time above.
- If the user wants to create or arrange an event, call add_calendar_event.
- If the user wants to view or summarize schedule, call query_calendar_events.
- For fuzzy office-time phrases like "tomorrow morning", infer a reasonable time if safe and mention the assumption in the final reply.
- Default reminder is 15 minutes before the event.
- The frontend executes calendar changes through EventKit, so tool calls should describe the exact intended action.
- If essential details are missing and cannot be safely inferred, ask one concise clarification question instead of calling a tool.
- This version only supports adding and querying calendar events. If the user asks to modify or delete an existing event, explain politely that the current version supports only adding and viewing schedule.
`.trim();
}

function buildMessages({ userId, text, timezone, calendarContext }) {
  const history = getConversation(userId);
  const messages = [
    { role: "system", content: getSystemPrompt(timezone) }
  ];

  if (Array.isArray(calendarContext?.events) && calendarContext.events.length > 0) {
    messages.push({
      role: "system",
      content: `Local calendar context from the device: ${serializeCalendarContext(calendarContext)}`
    });
  }

  messages.push(...history);
  messages.push({ role: "user", content: text });

  return messages;
}

function safeParseArguments(rawArguments) {
  if (!rawArguments) {
    return {};
  }

  try {
    return JSON.parse(rawArguments);
  } catch (error) {
    console.warn("Failed to parse tool arguments:", rawArguments);
    return {};
  }
}

function normalizeStructuredAction(toolCall) {
  if (!toolCall?.function) {
    return null;
  }

  const args = safeParseArguments(toolCall.function.arguments);

  if (toolCall.function.name === "add_calendar_event") {
    return {
      type: "add_calendar_event",
      payload: {
        title: args.title || "",
        startISO: args.startISO || "",
        durationHours: Number(args.durationHours || 1),
        notes: args.notes || "",
        location: args.location || "",
        reminderMinutesBefore: Number(args.reminderMinutesBefore || 15)
      }
    };
  }

  if (toolCall.function.name === "query_calendar_events") {
    return {
      type: "query_calendar_events",
      payload: {
        dateISO: args.dateISO || "",
        rangeDays: Number(args.rangeDays || 1),
        focus: args.focus || ""
      }
    };
  }

  return null;
}

function buildToolResult(structuredAction, calendarContext) {
  if (!structuredAction) {
    return "No tool action was selected.";
  }

  if (structuredAction.type === "add_calendar_event") {
    return JSON.stringify({
      status: "planned",
      event: structuredAction.payload,
      instruction: "The iOS client should add this event through EventKit."
    });
  }

  if (structuredAction.type === "query_calendar_events") {
    return JSON.stringify({
      status: "planned",
      query: structuredAction.payload,
      localEvents: Array.isArray(calendarContext?.events) ? calendarContext.events : [],
      instruction: "The iOS client should use EventKit data to fulfill the query."
    });
  }

  return "Unsupported action.";
}

async function runIntentAndPlanning({ userId, text, timezone, calendarContext }) {
  const model = chooseModel(text);
  const messages = buildMessages({ userId, text, timezone, calendarContext });

  const completion = await client.chat.completions.create({
    model,
    temperature: 0.2,
    tool_choice: "auto",
    tools: calendarTools,
    messages
  });

  const assistantMessage = completion.choices[0]?.message || {};
  const toolCall = assistantMessage.tool_calls?.[0] || null;
  const structuredAction = normalizeStructuredAction(toolCall);

  return {
    model,
    messages,
    assistantMessage,
    structuredAction
  };
}

async function generateFinalReply({ model, messages, assistantMessage, structuredAction, calendarContext }) {
  if (!structuredAction) {
    return assistantMessage.content || "我已了解您的需求，請再告訴我更多細節，我就能為您處理。";
  }

  const toolCall = assistantMessage.tool_calls?.[0];
  const followUpMessages = [
    ...messages,
    {
      role: "assistant",
      content: assistantMessage.content || "",
      tool_calls: assistantMessage.tool_calls
    },
    {
      role: "tool",
      tool_call_id: toolCall.id,
      content: buildToolResult(structuredAction, calendarContext)
    },
    {
      role: "system",
      content: "Write a concise Simplified Chinese response in a warm, polished secretary tone. Confirm the action clearly. Add one practical suggestion only when useful."
    }
  ];

  const completion = await client.chat.completions.create({
    model,
    temperature: 0.35,
    messages: followUpMessages
  });

  return completion.choices[0]?.message?.content || "我已為您整理好安排。";
}

async function streamFinalReply({ res, model, messages, assistantMessage, structuredAction, calendarContext }) {
  if (!structuredAction) {
    const plainReply = assistantMessage.content || "我已了解您的需求，請再告訴我更多細節，我就能為您處理。";
    const parts = plainReply.match(/.{1,18}/g) || [plainReply];

    for (const part of parts) {
      res.write(`data: ${JSON.stringify({ type: "token", content: part })}\n\n`);
      await new Promise((resolve) => setTimeout(resolve, 20));
    }

    return plainReply;
  }

  const toolCall = assistantMessage.tool_calls?.[0];
  const stream = await client.chat.completions.create({
    model,
    temperature: 0.35,
    stream: true,
    messages: [
      ...messages,
      {
        role: "assistant",
        content: assistantMessage.content || "",
        tool_calls: assistantMessage.tool_calls
      },
      {
        role: "tool",
        tool_call_id: toolCall.id,
        content: buildToolResult(structuredAction, calendarContext)
      },
      {
        role: "system",
        content: "Reply in Simplified Chinese with a warm, concise executive secretary tone."
      }
    ]
  });

  let finalReply = "";

  for await (const chunk of stream) {
    const delta = chunk.choices?.[0]?.delta?.content || "";
    if (!delta) {
      continue;
    }

    finalReply += delta;
    res.write(`data: ${JSON.stringify({ type: "token", content: delta })}\n\n`);
  }

  return finalReply || "我已為您整理好安排。";
}

function validateBody(body) {
  if (!body?.userId || !body?.text) {
    return "userId and text are required";
  }

  return null;
}

app.get("/health", (_req, res) => {
  res.json({
    ok: true,
    service: "kkpp-backend",
    timezone: defaultTimezone,
    timestamp: new Date().toISOString()
  });
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
    calendarContext = {}
  } = req.body;

  try {
    const pipeline = await runIntentAndPlanning({ userId, text, timezone, calendarContext });
    const reply = await generateFinalReply({
      ...pipeline,
      calendarContext
    });

    saveMessage(userId, "user", text);
    saveMessage(userId, "assistant", reply);

    return res.json({
      reply,
      structuredAction: pipeline.structuredAction
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
    calendarContext = {}
  } = req.body;

  res.setHeader("Content-Type", "text/event-stream; charset=utf-8");
  res.setHeader("Cache-Control", "no-cache, no-transform");
  res.setHeader("Connection", "keep-alive");
  res.flushHeaders?.();

  try {
    const pipeline = await runIntentAndPlanning({ userId, text, timezone, calendarContext });

    res.write(`data: ${JSON.stringify({ type: "action", structuredAction: pipeline.structuredAction })}\n\n`);

    const reply = await streamFinalReply({
      res,
      ...pipeline,
      calendarContext
    });

    saveMessage(userId, "user", text);
    saveMessage(userId, "assistant", reply);

    res.write(`data: ${JSON.stringify({ type: "done", reply, structuredAction: pipeline.structuredAction })}\n\n`);
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
