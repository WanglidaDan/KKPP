import SwiftUI

struct RecordingButton: View {
    let isRecording: Bool
    let actionStart: () -> Void
    let actionEnd: () -> Void

    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: isRecording
                        ? [Color.red, Color.orange]
                        : [Color(red: 0.10, green: 0.44, blue: 0.90), Color(red: 0.05, green: 0.70, blue: 0.76)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 88, height: 88)
            .overlay(
                Image(systemName: isRecording ? "waveform.circle.fill" : "mic.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .scaleEffect(isRecording ? 1.08 : 1.0)
            .shadow(color: .black.opacity(0.16), radius: 20, x: 0, y: 12)
            .animation(.spring(response: 0.28, dampingFraction: 0.65), value: isRecording)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in actionStart() }
                    .onEnded { _ in actionEnd() }
            )
    }
}
