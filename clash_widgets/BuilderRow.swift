import SwiftUI

struct BuilderRow: View {
    let upgrade: BuildingUpgrade
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(upgrade.name)
                    .font(.headline)
                Text("To Level \(upgrade.targetLevel)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text(upgrade.timeRemaining)
                    .font(.headline)
                    .foregroundColor(.orange)
                Text("remaining")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}