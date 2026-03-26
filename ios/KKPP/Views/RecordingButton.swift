import SwiftUI

struct RecordingButton: View {
    let isRecording: Bool
    let actionStart: () -> Void
    let actionEnd: () -> Void

    var body: some View {
        ZStack {
            Circle()
                .fill(isRecording ? Color.red.opacity(0.14) : Color.blue.opacity(0.10))
                .frame(width: 44, height: 44)

            Circle()
                .fill(
                    LinearGradient(
                        colors: isRecording
                            ? [Color(red: 0.96, green: 0.34, blue: 0.30), Color(red: 0.91, green: 0.51, blue: 0.28)]
                            : [Color.white, Color.white.opacity(0.96)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 38, height: 38)
                .overlay(
                    Image(systemName: isRecording ? "waveform" : "mic.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(isRecording ? .white : .blue)
                )
                .overlay(
                    Circle()
                        .strokeBorder(isRecording ? Color.red.opacity(0.25) : Color.black.opacity(0.06), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.10), radius: 10, x: 0, y: 4)
        }
        .scaleEffect(isRecording ? 1.05 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.72), value: isRecording)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in actionStart() }
                .onEnded { _ in actionEnd() }
        )
    }
}
