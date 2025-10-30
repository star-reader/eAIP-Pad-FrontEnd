import SwiftUI
import SwiftData

// MARK: - 细则视图
struct RegulationsView: View {
    @State private var searchText = ""
    @State private var selectedCategory: RegulationCategory = .all
    @State private var isLoading = false
    @State private var regulations: [RegulationItem] = []
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 搜索栏
                SearchBar(text: $searchText, placeholder: "搜索细则...")
                    .padding()
                
                // 分类选择
                CategoryPicker(selectedCategory: $selectedCategory)
                    .padding(.horizontal)
                
                // 细则列表
                if isLoading {
                    Spacer()
                    ProgressView("加载中...")
                        .progressViewStyle(CircularProgressViewStyle(tint: .primaryBlue))
                    Spacer()
                } else if regulations.isEmpty {
                    ContentUnavailableView(
                        "暂无细则",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("当前分类下没有找到相关细则")
                    )
                    .foregroundColor(.primaryBlue)
                } else {
                    List(filteredRegulations) { regulation in
                        RegulationRow(regulation: regulation)
                    }
                    .listStyle(PlainListStyle())
                }
            }
            .navigationTitle("细则")
            .navigationBarTitleDisplayMode(.large)
            .refreshable {
                await loadRegulations()
            }
        }
        .onAppear {
            Task {
                await loadRegulations()
            }
        }
    }
    
    // MARK: - 过滤后的细则
    private var filteredRegulations: [RegulationItem] {
        var filtered = regulations
        
        // 按分类过滤
        if selectedCategory != .all {
            filtered = filtered.filter { $0.category == selectedCategory }
        }
        
        // 按搜索文本过滤
        if !searchText.isEmpty {
            filtered = filtered.filter { regulation in
                regulation.title.localizedCaseInsensitiveContains(searchText) ||
                regulation.description.localizedCaseInsensitiveContains(searchText) ||
                regulation.code.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return filtered
    }
    
    // MARK: - 加载细则
    private func loadRegulations() async {
        await MainActor.run {
            isLoading = true
        }
        
        // 模拟加载数据
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        await MainActor.run {
            regulations = RegulationItem.mockData
            isLoading = false
        }
    }
}

// MARK: - 搜索栏
struct SearchBar: View {
    @Binding var text: String
    let placeholder: String
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField(placeholder, text: $text)
                .textFieldStyle(PlainTextFieldStyle())
            
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - 分类选择器
struct CategoryPicker: View {
    @Binding var selectedCategory: RegulationCategory
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(RegulationCategory.allCases, id: \.self) { category in
                    Button {
                        selectedCategory = category
                    } label: {
                        Text(category.displayName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(selectedCategory == category ? Color.primaryBlue : Color.clear)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 20)
                                            .stroke(Color.primaryBlue, lineWidth: 1)
                                    )
                            )
                            .foregroundColor(selectedCategory == category ? .white : .primaryBlue)
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}

// MARK: - 细则行
struct RegulationRow: View {
    let regulation: RegulationItem
    
    var body: some View {
        NavigationLink {
            RegulationDetailView(regulation: regulation)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(regulation.code)
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(regulation.category.color.opacity(0.2))
                        .foregroundColor(regulation.category.color)
                        .cornerRadius(6)
                    
                    Spacer()
                    
                    Text(regulation.effectiveDate, style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text(regulation.title)
                    .font(.headline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                
                Text(regulation.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                
                HStack {
                    Label(regulation.category.displayName, systemImage: regulation.category.icon)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if regulation.isNew {
                        Text("新")
                            .font(.caption)
                            .fontWeight(.bold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.red)
                            .foregroundColor(.white)
                            .cornerRadius(4)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - 细则详情视图
struct RegulationDetailView: View {
    let regulation: RegulationItem
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 标题区域
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(regulation.code)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(regulation.category.color.opacity(0.2))
                            .foregroundColor(regulation.category.color)
                            .cornerRadius(8)
                        
                        Spacer()
                        
                        if regulation.isNew {
                            Text("新")
                                .font(.caption)
                                .fontWeight(.bold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.red)
                                .foregroundColor(.white)
                                .cornerRadius(6)
                        }
                    }
                    
                    Text(regulation.title)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    HStack {
                        Label(regulation.category.displayName, systemImage: regulation.category.icon)
                        
                        Spacer()
                        
                        Text("生效日期: \(regulation.effectiveDate, style: .date)")
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }
                
                Divider()
                
                // 内容区域
                VStack(alignment: .leading, spacing: 16) {
                    Text("细则内容")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text(regulation.content)
                        .font(.body)
                        .lineSpacing(4)
                }
                
                if !regulation.attachments.isEmpty {
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("相关附件")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        ForEach(regulation.attachments, id: \.self) { attachment in
                            HStack {
                                Image(systemName: "doc.fill")
                                    .foregroundColor(.primaryBlue)
                                Text(attachment)
                                    .font(.subheadline)
                                Spacer()
                                Image(systemName: "arrow.down.circle")
                                    .foregroundColor(.primaryBlue)
                            }
                            .padding()
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("细则详情")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 细则分类枚举
enum RegulationCategory: String, CaseIterable {
    case all = "all"
    case flight = "flight"
    case airspace = "airspace"
    case airport = "airport"
    case weather = "weather"
    case communication = "communication"
    case navigation = "navigation"
    case emergency = "emergency"
    
    var displayName: String {
        switch self {
        case .all: return "全部"
        case .flight: return "飞行"
        case .airspace: return "空域"
        case .airport: return "机场"
        case .weather: return "气象"
        case .communication: return "通信"
        case .navigation: return "导航"
        case .emergency: return "应急"
        }
    }
    
    var icon: String {
        switch self {
        case .all: return "list.bullet"
        case .flight: return "airplane"
        case .airspace: return "cloud"
        case .airport: return "building"
        case .weather: return "cloud.rain"
        case .communication: return "antenna.radiowaves.left.and.right"
        case .navigation: return "location"
        case .emergency: return "exclamationmark.triangle"
        }
    }
    
    var color: Color {
        switch self {
        case .all: return .primary
        case .flight: return .primaryBlue
        case .airspace: return .skyBlue
        case .airport: return .aviationBlue
        case .weather: return .mutedBlue
        case .communication: return .accentBlue
        case .navigation: return .secondaryBlue
        case .emergency: return .errorRed
        }
    }
}

// MARK: - 细则项目模型
struct RegulationItem: Identifiable {
    let id = UUID()
    let code: String
    let title: String
    let description: String
    let content: String
    let category: RegulationCategory
    let effectiveDate: Date
    let isNew: Bool
    let attachments: [String]
    
    static let mockData: [RegulationItem] = [
        RegulationItem(
            code: "CCAR-91",
            title: "一般运行和飞行规则",
            description: "规定了民用航空器的一般运行和飞行规则，包括飞行准备、飞行程序等内容。",
            content: "本规则规定了在中华人民共和国境内进行民用航空活动应当遵守的一般运行和飞行规则...",
            category: .flight,
            effectiveDate: Date().addingTimeInterval(-86400 * 30),
            isNew: false,
            attachments: ["CCAR-91附件A.pdf", "CCAR-91附件B.pdf"]
        ),
        RegulationItem(
            code: "CCAR-121",
            title: "大型飞机公共航空运输承运人运行合格审定规则",
            description: "规定了使用大型飞机从事公共航空运输的承运人的运行合格审定要求。",
            content: "本规则规定了使用大型飞机从事公共航空运输的承运人应当具备的条件...",
            category: .flight,
            effectiveDate: Date().addingTimeInterval(-86400 * 60),
            isNew: true,
            attachments: []
        ),
        RegulationItem(
            code: "MH/T 4013",
            title: "民用机场飞行区技术标准",
            description: "规定了民用机场飞行区的设计、建设和维护技术标准。",
            content: "本标准规定了民用机场飞行区的跑道、滑行道、停机坪等设施的技术要求...",
            category: .airport,
            effectiveDate: Date().addingTimeInterval(-86400 * 90),
            isNew: false,
            attachments: ["技术标准图表.pdf"]
        )
    ]
}

#Preview {
    RegulationsView()
}