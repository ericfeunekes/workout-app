#if DEBUG
import SwiftUI
import HealthKitBridge

struct HealthKitProbeView: View {
    @State private var output: String = "Running HealthKit simulator probe..."

    var body: some View {
        ScrollView {
            Text(output)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.white)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .background(Color.black)
        .task {
            let result = await HealthKitSimulatorProbe.run()
            let json = HealthKitSimulatorProbe.encodedJSON(result)
            output = json
            writeProbeResult(json)
        }
    }

    private func writeProbeResult(_ json: String) {
        guard let documents = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else { return }
        let url = documents.appendingPathComponent("healthkit-simulator-probe.json")
        try? json.write(to: url, atomically: true, encoding: .utf8)
    }
}
#endif
