/// A language model the user set up in one module, for another to ask a short question of: the Translation module's "LLM tương thích
/// OpenAI" for the Media module to turn a page's title into a film's. The app hands it over; a module without one does without.
public protocol LanguageModel: AnyObject {
    /// `instruction` says what to do and holds nothing a user or a page wrote; `input` is that, sent as data. Throws when the model is
    /// not set up or the request fails; an error never holds the key.
    func complete(instruction: String, input: String) async throws -> String
}
