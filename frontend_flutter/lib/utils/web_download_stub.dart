/// Stub implementation for non-web platforms.
/// Downloading files is not supported, caller should fallback to clipboard.
void triggerMarkdownDownload(String content, String fileName) {
  // No-op on non-web platforms
}

void triggerCsvDownload(String content, String fileName) {
  // No-op on non-web platforms
}
