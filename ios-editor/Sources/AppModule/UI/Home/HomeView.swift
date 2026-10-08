import SwiftUI

/// Placeholder sample data only — no backend/catalog exists yet. Thumbnails
/// are gradients (no real template media to show), `isNew` drives the "New"
/// badge seen in the reference design.
struct TemplateSample: Identifiable {
    let id = UUID()
    let title: String
    let caption: String
    let gradient: [Color]
    let isNew: Bool
}

private enum HomeCategory: String, CaseIterable, Identifiable {
    case discover = "Discover"
    case carousels = "Carousels"
    case collages = "Collages"
    case stories = "Stories"

    var id: String { rawValue }
}

/// A horizontally-scrolling row of template cards, the repeated building
/// block both "Trends" and "Carousels" use.
private struct TemplateRow: View {
    let templates: [TemplateSample]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(templates) { template in
                    TemplateCard(template: template)
                }
            }
            .padding(.horizontal)
        }
    }
}

private struct TemplateCard: View {
    let template: TemplateSample

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: template.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)

            VStack {
                if template.isNew {
                    Text("New")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.9), in: Capsule())
                        .foregroundColor(.black)
                        .padding(12)
                }
                Spacer()
                HStack {
                    Text(template.title)
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                }
                Text(template.caption)
                    .font(.caption2)
                    .opacity(0.85)
            }
            .foregroundColor(.white)
            .padding(12)
        }
        .frame(width: 150, height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct HomeView: View {
    @State private var category: HomeCategory = .discover

    private let trends: [TemplateSample] = [
        TemplateSample(title: "Digital Memories", caption: "22s · 33 clips", gradient: [.purple, .black], isNew: true),
        TemplateSample(title: "Fall Diary", caption: "17s · 36 clips", gradient: [.orange, .brown], isNew: true),
        TemplateSample(title: "Night Out", caption: "26s · 65 clips", gradient: [.yellow, .orange], isNew: true),
        TemplateSample(title: "City Lights", caption: "19s · 28 clips", gradient: [.blue, .indigo], isNew: false),
    ]

    private let carousels: [TemplateSample] = [
        TemplateSample(title: "October Calendar", caption: "6 slides", gradient: [.red, .black], isNew: true),
        TemplateSample(title: "Random Moments", caption: "5 slides", gradient: [.gray, .black], isNew: true),
        TemplateSample(title: "October Gallery", caption: "8 slides", gradient: [.brown, .orange], isNew: true),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Picker("Category", selection: $category) {
                    ForEach(HomeCategory.allCases) { category in
                        Text(category.rawValue).tag(category)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Trends 🔥").font(.title2.bold())
                        .padding(.horizontal)
                    TemplateRow(templates: trends)
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Carousels").font(.title2.bold())
                        Image(systemName: "chevron.right").foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    Text("Design seamless carousels with ready-to-use templates")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                    TemplateRow(templates: carousels)
                }
            }
            .padding(.vertical)
        }
    }
}
