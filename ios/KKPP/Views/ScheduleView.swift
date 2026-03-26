import SwiftUI

struct ScheduleView: View {
    @ObservedObject var viewModel: ScheduleViewModel

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.98, green: 0.98, blue: 0.95),
                        Color(red: 0.93, green: 0.96, blue: 0.90)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                if viewModel.isLoading {
                    ProgressView("正在整理你的日程…")
                } else if let errorMessage = viewModel.errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "calendar.badge.exclamationmark")
                            .font(.system(size: 34))
                        Text(errorMessage)
                            .multilineTextAlignment(.center)
                        Button("重新加载") {
                            Task { await viewModel.refresh() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                } else if viewModel.events.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "calendar")
                            .font(.system(size: 34))
                        Text("今天到未来 7 天暂时没有新的安排。")
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            ForEach(viewModel.events) { event in
                                ScheduleRowView(event: event)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("我的日程")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("刷新") {
                        Task { await viewModel.refresh() }
                    }
                }
            }
        }
        .task {
            await viewModel.refresh()
        }
    }
}
