import ClipboardMCPKit
import Foundation

// An AI agent starts this as an MCP server and speaks JSON-RPC to it on stdin and stdout. It answers from the running MyNotch
// over a socket in the user's private folder; stdout carries nothing but MCP messages, and a closed pipe must end it quietly,
// not with SIGPIPE.
signal(SIGPIPE, SIG_IGN)
ClipboardMCPHelper.run()
