/// Vietnamese strings for Settings → Browser (the browser-agent engine, its
/// settings form, Chrome extension pairing and Activity) and the Browser
/// slot/type added to Settings → Runtime. English string = key. Words
/// shared with other screens ("Auto", "Advanced", "Connected", "Approve",
/// "Remove", "Activity", "General", "Save", "Cancel"…) live in their own
/// maps and are not repeated here.
///
/// "Add site" already exists (plugins_misc.dart, "Thêm trang" — the sandbox
/// allowed-sites list) with a different Vietnamese value than this screen's
/// spec ("Thêm site"); reusing the shared key rather than redefining it, per
/// the app's own "never redefine a shared key with a different value" rule.
const Map<String, String> viBrowser = {
  // Settings nav + Runtime catalog type filter
  'Browser': 'Trình duyệt',

  // Engine status
  'Browser engine': 'Engine trình duyệt',
  'Engine in use': 'Engine đang dùng',
  'New (Jev + LLM)': 'Mới (Jev + LLM)',
  'Legacy (extension scripts)': 'Cũ (script trong extension)',
  'The Browser runtime is not installed.': 'Runtime Browser chưa được cài.',
  'The decision model is not installed:': 'Mô hình quyết định chưa được cài:',
  'Every browser step is then chosen by the chat model: seconds per step instead of a fraction of one.':
      'Khi đó mỗi bước duyệt web do mô hình chat chọn: mất vài giây mỗi bước thay vì chưa tới một giây.',
  'Open Decision settings': 'Mở cài đặt Decision',

  // Settings form — General
  'Engine': 'Engine',
  'Auto uses the new engine once the Browser runtime is installed. Applies to chats started afterwards.':
      'Tự động dùng engine mới khi đã cài runtime Browser. Áp dụng cho các cuộc trò chuyện mở sau đó.',
  'Default browser': 'Trình duyệt mặc định',
  "SenClaw's own Chrome": 'Chrome riêng của SenClaw',
  'Your Chrome (extension)': 'Chrome của bạn (extension)',
  "Run SenClaw's Chrome without a window": 'Chạy Chrome của SenClaw không hiện cửa sổ',
  'Chrome profile name': 'Tên profile Chrome',
  'Step budget': 'Số bước tối đa',
  'Start page': 'Trang bắt đầu',

  // Settings form — Decisions
  'Decisions': 'Quyết định',
  'Decision backend': 'Backend quyết định',
  'Auto (local, hosted only for allowed sites)': 'Tự động (cục bộ, hosted chỉ cho site được phép)',
  'Local model only': 'Chỉ model cục bộ',
  'Hosted Jev': 'Jev hosted',
  'LLM only (no decision model)': 'Chỉ LLM (không dùng model quyết định)',
  'Local decision model': 'Model quyết định cục bộ',
  'Hosted model': 'Model hosted',
  'Sites allowed for hosted decisions': 'Site được dùng quyết định hosted',
  "Only these sites' page text may go to the hosted decision model.":
      'Chỉ nội dung trang của các site này được gửi tới model quyết định hosted.',
  'Sensitive sites': 'Site nhạy cảm',
  'Always decided locally, with stricter rules.': 'Luôn quyết định cục bộ, với luật chặt hơn.',
  'Text writer model': 'Model viết chữ',
  'Fallback model': 'Model dự phòng',
  'Active chat model': 'Model chat đang dùng',

  // Settings form — Sites
  'Sites': 'Site',
  'Browser per site': 'Trình duyệt theo site',

  // Settings form — Advanced
  'Confidence bands': 'Ngưỡng tin cậy',
  'Act at or above': 'Tự làm từ mức',
  'Ask the LLM at or above': 'Hỏi LLM từ mức',
  'Local': 'Cục bộ',
  'Hosted': 'Hosted',

  // Chrome extension
  'Chrome extension': 'Extension Chrome',
  'Not connected': 'Chưa kết nối',
  'Waiting to pair': 'Đang chờ ghép cặp',
  'Paired browsers': 'Trình duyệt đã ghép cặp',
  'This browser will need to pair again.': 'Trình duyệt này sẽ phải ghép cặp lại.',
  'Install the SenClaw extension in Chrome and open its side panel; its pairing code appears here — or send `pair approve <CODE>` in any chat.':
      'Cài extension SenClaw trong Chrome và mở side panel; mã ghép cặp sẽ hiện ở đây — hoặc gửi `pair approve <MÃ>` trong bất kỳ cuộc trò chuyện nào.',

  // Activity
  'Show open tabs': 'Xem các tab đang mở',
  'No open tabs': 'Không có tab nào đang mở',

  // Save
  'Settings saved': 'Đã lưu cài đặt',

  // Waiting for your approval. "Approve" and "Goal" are shared keys defined
  // elsewhere (settings_screen.dart, kanban.dart) with the same Vietnamese
  // value this screen's spec calls for — reused, not repeated, per this
  // file's own rule above.
  'Waiting for your approval': 'Đang chờ bạn duyệt',
  'A browser task paused before this action. Approve only if you want SenClaw to do it.':
      'Một tác vụ trình duyệt đã dừng lại trước thao tác này. Chỉ duyệt khi bạn muốn SenClaw thực hiện nó.',
  'SenClaw will do this in the browser now.': 'SenClaw sẽ thực hiện thao tác này trên trình duyệt ngay bây giờ.',
  'Decline': 'Từ chối',
  'Declined': 'Đã từ chối',
  'Waiting {time}': 'Đã chờ {time}',
  'The task went on: {status} — {message}': 'Tác vụ đã tiếp tục: {status} — {message}',
  'Click': 'Nhấp',
  'Press Enter': 'Nhấn Enter',
  'Confirm a dialog': 'Xác nhận hộp thoại',
  'Type text': 'Nhập chữ',

  // Downloading the decision model. "Cancel", "Retry" and "Download" are
  // shared keys in common.dart; "Open Runtime settings" lives in runtime.dart.
  'Download ({size})': 'Tải về ({size})',
  'Checking the downloaded files': 'Đang kiểm tra các file đã tải',
  'Preparing the download': 'Đang chuẩn bị tải',
  'The download failed:': 'Tải về thất bại:',
  'The decision runtime is not installed.': 'Runtime quyết định (sen-sysone) chưa được cài.',
  'The decision model is installed.': 'Đã cài xong mô hình quyết định.',
};
