/// Vietnamese strings for this area. English string = key. Filled by the
/// localization sweep; keep entries sorted roughly by screen order.
const Map<String, String> viChatWidgets = {
  // file_pane — the files a chat opened
  'Search in file': 'Tìm trong tệp',
  'Contents': 'Mục lục',
  'View source': 'Xem mã nguồn',
  'View rendered': 'Xem bản hiển thị',
  'Close file': 'Đóng tệp',
  'Previous match': 'Kết quả trước',
  'Next match': 'Kết quả sau',
  'Cannot open {name}': 'Không mở được {name}',
  'Cannot show {name}': 'Không hiển thị được {name}',
  'This file does not exist, or the path is a folder.':
      'Tệp này không tồn tại, hoặc đường dẫn là một thư mục.',
  'The path is relative and this chat has no working folder.':
      'Đường dẫn là tương đối và cuộc trò chuyện này không có thư mục làm việc.',
  'This is a binary file, not text.': 'Đây là tệp nhị phân, không phải văn bản.',
  'This file is over 512 KB and could not be read as text.':
      'Tệp này lớn hơn 512 KB và không đọc được dưới dạng văn bản.',
  'SenClaw did not answer in time.': 'SenClaw không phản hồi kịp.',
  'The diagram renderer did not respond.':
      'Bộ vẽ sơ đồ không phản hồi.',
  // Mermaid diagram fallback on a platform with no embedded webview.
  'Diagrams need macOS or Windows to draw here.':
      'Sơ đồ chỉ vẽ được trên macOS hoặc Windows.',
  // widget_card.dart — inline widget chrome (series names & payload stay data)
  'Unknown widget: "{kind}"': 'Widget không xác định: "{kind}"',
  'No chart data': 'Không có dữ liệu biểu đồ',
  'Image unavailable': 'Ảnh không khả dụng',
  'Failed to load image': 'Không tải được ảnh',
  'Video needs a playable http(s) URL (not a file path).':
      'Video cần một URL http(s) phát được (không dùng đường dẫn file).',
  'Audio needs a playable http(s) URL (not a file path).':
      'Audio cần một URL http(s) phát được (không dùng đường dẫn file).',
  'Open externally': 'Mở ngoài',
  'Play': 'Phát',
  'Widget {id} is unavailable — open the app in Apps to view it.':
      'Widget {id} không khả dụng — mở app trong mục Apps để xem.',
  'Click to load widget': 'Bấm để tải widget',
  // _PlanCard — live task checklist card (widget_card.dart)
  'Plan': 'Kế hoạch',
  'Plan has no items': 'Kế hoạch không có mục nào',
  // Fallback heading for an uncaptioned video card. Unchanged in Vietnamese —
  // the key exists so other locales have a hook.
  'Video': 'Video',

  // message_widgets.dart — bubbles, message actions, timestamps
  'now': 'bây giờ',
  '{n}m': '{n} phút',
  // Token count under a bubble. "tok" is the same abbreviation in Vietnamese.
  '{n} tok': '{n} tok',
  'Save note': 'Lưu ghi chú',
  'Saved': 'Đã lưu',
  'Play (TTS)': 'Phát (TTS)',
  'Speaking…': 'Đang đọc…',
  'TTS failed': 'Lỗi TTS',
  'think': 'suy nghĩ',

  // message_widgets.dart — permission card
  'Permission required': 'Cần cấp quyền',
  'Resolved: {key}': 'Đã xử lý: {key}',
  'answered': 'đã trả lời',

  // message_widgets.dart — tool group verbs
  'Read a file': 'Đọc tệp',
  'Created a file': 'Tạo tệp',
  'Edited a file': 'Sửa tệp',
  'Ran a command': 'Chạy lệnh',
  // A file step's row: the verb, then the file's name ("Đọc main.dart").
  'Read': 'Đọc',
  'Wrote': 'Ghi',
  'Updated': 'Cập nhật',
  // Collapsed tool group: what it did, counted by kind ("Đọc 3 tệp, chạy 2 lệnh").
  'Read {n} files': 'Đọc {n} tệp',
  'Wrote {n} files': 'Ghi {n} tệp',
  'Wrote a file': 'Ghi tệp',
  '({n} failed)': '({n} lỗi)',
  'Edited {n} files': 'Sửa {n} tệp',
  'Ran {n} commands': 'Chạy {n} lệnh',
  'Used {n} tools': 'Dùng {n} công cụ',
  // changes_tab.dart — turn a checkpoint into a documentation page
  'Ghi tài liệu': 'Ghi tài liệu',
  'Đã ghi {path}': 'Đã ghi {path}',
  'Ghi thành một trang .md trong docs/changes của dự án. Không commit.':
      'Ghi thành một trang .md trong docs/changes của dự án. Không commit.',
  'Searched files': 'Tìm tệp',
  'Searched content': 'Tìm nội dung',
  'Fetched a URL': 'Tải một URL',
  'Searched the web': 'Tìm trên web',
  'Discovered a tool': 'Tra cứu công cụ',
  'Invoked a skill': 'Gọi skill',
  'Spawned a subagent': 'Tạo agent con',
  'Browser action': 'Thao tác trình duyệt',
  'Memory lookup': 'Tra cứu bộ nhớ',
  'Wiki action': 'Thao tác Wiki',
  'Used a tool': 'Dùng công cụ',

  // message_widgets.dart — diff view + dispatch card
  'New file': 'Tệp mới',
  '{size} bytes': '{size} byte',
  '… {n} more lines': '… còn {n} dòng',
  'Dispatch': 'Điều phối',

  // form_card.dart — FormUI chrome (field labels/options come from the agent)
  'Form': 'Biểu mẫu',
  'Submit': 'Gửi',
  'Submitted': 'Đã gửi',
  '{n} required field left': 'Còn {n} trường bắt buộc',
  '{n} required fields left': 'Còn {n} trường bắt buộc',
  'Skip': 'Bỏ qua',
  'Select…': 'Chọn…',
  'Pick a date…': 'Chọn ngày…',
  'Add row': 'Thêm hàng',
  '(unsupported field: {type})': '(trường không hỗ trợ: {type})',

  // question_card.dart — AskUserQuestion chrome (questions/options are data)
  'Question': 'Câu hỏi',
  'Answered': 'Đã trả lời',
  'Other': 'Khác',
  'Your answer…': 'Câu trả lời của bạn…',

  // plan_exit_dialog.dart — the two button labels are the daemon's defaults
  // (plan_provider.dart); a custom label from the daemon passes through.
  'Plan ready for review': 'Kế hoạch sẵn sàng để duyệt',
  '_No plan content._': '_Không có nội dung kế hoạch._',
  'Approve plan and start editing': 'Duyệt kế hoạch và bắt đầu chỉnh sửa',
  'Clear context and start fresh': 'Xoá ngữ cảnh và bắt đầu lại',

  // Tool parameter rendering (ToolParams)
  'Yes': 'Có',
  'No': 'Không',

  // slash_mention_input.dart — spec-flow commands in the / menu
  '<idea> — explore it and write a brief in docs/designs/':
      '<ý tưởng> — khám phá và viết bản tóm tắt trong docs/designs/',
  '[path] — turn the open brief into a full spec':
      '[đường dẫn] — biến bản tóm tắt đang mở thành spec đầy đủ',
  '[path] — four reviewers with no context check the spec':
      '[đường dẫn] — bốn người duyệt không có ngữ cảnh kiểm tra spec',
  '[force] — approve the reviewed spec; code changes unlock':
      '[force] — duyệt spec đã review; mở khoá sửa code',
  '[use <path>|done|skip] — show, switch, close or skip the open spec':
      '[use <đường dẫn>|done|skip] — xem, chuyển, đóng hoặc bỏ qua spec đang mở',
};
