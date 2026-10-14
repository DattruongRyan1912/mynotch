import Foundation
import YouTubeBridgeKit

// Chrome starts this for the MyNotch YouTube extension and writes native messages to stdin; it passes them to the app
// and never prints or fails (see YouTubeHostCLI).
exit(YouTubeHostCLI.run(
    stdin: FileDescriptorReader(fileDescriptor: STDIN_FILENO),
    socketPath: YouTubeSocket.defaultPath()
))
