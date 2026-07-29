import Foundation

func byteCount(_ value: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
}

func byteRate(_ value: Int64) -> String {
    "\(byteCount(value))/s"
}
