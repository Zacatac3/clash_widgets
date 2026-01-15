import Foundation
import Combine

class APIClient: ObservableObject {
    @Published var playerProfile: PlayerProfile?
    @Published var isLoading = false
    @Published var errorMessage: String?

    func fetchPlayerProfile(playerTag: String, apiKey: String) {
        let cleanTag = playerTag.replacingOccurrences(of: "#", with: "")
        let urlString = "https://cocproxy.royaleapi.dev/v1/players/%23\(cleanTag)"
        
        guard let url = URL(string: urlString) else {
            self.errorMessage = "Invalid URL"
            return
        }
        
        var request = URLRequest(url: url)
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        self.isLoading = true
        self.errorMessage = nil
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            OperationQueue.main.addOperation {
                self.isLoading = false
                
                if let error = error {
                    self.errorMessage = error.localizedDescription
                    return
                }
                
                guard let data = data else {
                    self.errorMessage = "No data received"
                    return
                }
                
                do {
                    let profile = try JSONDecoder().decode(PlayerProfile.self, from: data)
                    self.playerProfile = profile
                } catch {
                    self.errorMessage = "Decoding error: \(error.localizedDescription)"
                    print("Decoding error: \(error)")
                }
            }
        }.resume()
    }
}
