/// Vietnamese strings for this area. English string = key. Filled by the
/// localization sweep; keep entries sorted roughly by screen order.
///
/// Area: Knowledge (cognitive graph + data list), Wiki, Diagnostics.
/// Keys already covered by `common.dart` (Cancel, Save, Delete, Edit, Create,
/// OK, Close, Add, Reload, Refresh, Download, History, Logs, No results) are
/// intentionally absent — this map is merged after `viCommon`, so repeating a
/// key here would override it everywhere in the app.
const Map<String, String> viCognitiveWiki = {
  // ── Knowledge — header ──────────────────────────────────────────────────
  'User info aggregated from chats · extended with '
      'uploaded documents · Recall researches it for detailed, '
      'grounded answers':
      'Thông tin về bạn được tổng hợp từ các cuộc trò chuyện · mở rộng bằng '
          'tài liệu bạn tải lên · Recall tra cứu để trả lời chi tiết, có dẫn '
          'chứng',
  'Knowledge': 'Tri thức',
  'nodes': 'nút',
  'edges': 'cạnh',
  'Graph': 'Đồ thị',
  'Data': 'Dữ liệu',
  '🌐 All knowledge': '🌐 Toàn bộ tri thức',
  'Add knowledge': 'Thêm tri thức',

  // ── Knowledge — facts (what the agent remembers from conversations) ─────
  // 'Agent', 'Kind' and 'Forget' are defined elsewhere; 'Cancel', 'Refresh'
  // live in common.dart.
  'Facts': 'Fact (sự thật đã nhớ)',
  'Fact': 'Fact',
  'When': 'Khi nào',
  'Said': 'Số lần nhắc',
  'Forgotten': 'Đã quên',
  'Forget this fact?': 'Quên fact này?',
  'The agent will stop recalling it.': 'Agent sẽ không nhắc lại nó nữa.',
  'Forget failed: {error}': 'Quên không được: {error}',
  'Load failed: {error}': 'Tải không được: {error}',
  'replaced': 'đã bị thay',
  'The person changed their mind; the newer fact replaced this one. '
      'Forgetting the newer fact brings this one back.':
      'Người dùng đã đổi ý; fact mới hơn đã thay fact này. Quên fact mới thì '
          'fact này sống lại.',
  'said {date}': 'nói ngày {date}',
  'No date in the fact; this is the day it was said.':
      'Fact không có ngày; đây là ngày nó được nhắc tới.',
  'Something about the world or the person.':
      'Điều gì đó về thế giới hoặc về người dùng.',
  'Something the agent itself did or experienced.':
      'Điều agent đã làm hoặc trải qua.',
  'Dated statements the agent picked out of your conversations. '
      'They are recalled automatically in later chats — forget any '
      'that are wrong or that you did not want kept.':
      'Những câu có ngày mà agent rút ra từ các cuộc trò chuyện của bạn. '
          'Chúng được nhớ lại tự động ở các lượt sau — hãy quên những fact '
          'sai hoặc bạn không muốn giữ.',
  'The fact store has not started yet — try again in a moment.':
      'Kho fact chưa khởi động xong — thử lại sau giây lát.',
  'No agent has facts yet': 'Chưa có agent nào có fact',
  'Search facts…': 'Tìm fact…',
  'Also list facts that were replaced. A keyword search never shows them.':
      'Hiện cả fact đã bị thay. Tìm theo từ khoá thì không bao giờ hiện chúng.',
  'Show replaced': 'Hiện fact đã bị thay',
  'Show replaced ({n})': 'Hiện fact đã bị thay ({n})',
  'Nothing remembered yet. Facts appear here a minute or two after a '
      'conversation goes quiet.':
      'Chưa nhớ gì. Fact xuất hiện ở đây một–hai phút sau khi cuộc trò '
          'chuyện im.',
  'No fact matches that search.': 'Không fact nào khớp tìm kiếm này.',
  'Said in this chat; only this chat recalls it.':
      'Nói trong cuộc trò chuyện này; chỉ cuộc trò chuyện này nhớ lại nó.',
  'This agent has no facts.': 'Agent này chưa có fact nào.',

  // ── Knowledge — maintenance menu ────────────────────────────────────────
  'Maintenance': 'Bảo trì',
  'Maintain': 'Bảo trì',
  'Re-extract pending': 'Trích xuất lại phần còn chờ',
  'Cleanup': 'Dọn dẹp',
  'Decay log': 'Nhật ký suy giảm',
  'Maintenance run': 'Đã chạy bảo trì',
  'Cleanup done': 'Đã dọn dẹp',
  'Backfill started': 'Đã bắt đầu bù dữ liệu',
  'removed {n} node(s)': 'đã xoá {n} nút',
  '{n} chunk(s) queued': 'đã xếp hàng {n} đoạn',
  'No runs yet': 'Chưa có lần chạy nào',
  'scanned {scanned} · pruned {pruned} · promoted {promoted}':
      'quét {scanned} · tỉa {pruned} · nâng {promoted}',

  // ── Knowledge — data list & node detail ─────────────────────────────────
  'Search knowledge…': 'Tìm trong tri thức…',
  'No nodes': 'Chưa có nút nào',
  'Select a node': 'Chọn một nút',
  'Re-extract': 'Trích xuất lại',
  'Forget': 'Quên',
  '(no content)': '(không có nội dung)',

  // ── Knowledge — add / upload dialog ─────────────────────────────────────
  'What to remember…': 'Cần nhớ điều gì…',
  'tags, comma, separated': 'thẻ, ngăn, bằng dấu phẩy',
  'or': 'hoặc',
  'Upload a file': 'Tải lên một tệp',
  '{name}: added to knowledge': '{name}: đã thêm vào tri thức',
  'Upload failed: {err}': 'Tải lên thất bại: {err}',

  // ── Knowledge — Recall dialog ───────────────────────────────────────────
  'Recall — grounded answer': 'Recall — câu trả lời có dẫn chứng',
  'Ask a question…': 'Đặt một câu hỏi…',
  'Hybrid (vec+FTS)': 'Kết hợp (vec+FTS)',
  'Keyword (FTS)': 'Từ khoá (FTS)',
  'Ask': 'Hỏi',
  'SOURCES ({n})': 'NGUỒN ({n})',

  // ── Knowledge — graph explorer ──────────────────────────────────────────
  'Graph error: {err}': 'Lỗi đồ thị: {err}',
  'Not enough connected nodes to graph': 'Không đủ nút liên kết để vẽ đồ thị',
  'No graph data yet': 'Chưa có dữ liệu đồ thị',
  '{n} nodes': '{n} nút',
  '{n} edges': '{n} cạnh',
  'Search nodes…': 'Tìm nút…',
  'Chunks': 'Đoạn',
  'Graph truncated': 'Đồ thị đã bị cắt bớt',
  'Drag node = move · Scroll = zoom · Tap node = focus':
      'Kéo nút = di chuyển · Cuộn = thu phóng · Chạm nút = chọn',
  'Open in data view': 'Mở trong chế độ Dữ liệu',
  '{n} connections': '{n} liên kết',
  'No connections': 'Không có liên kết',
  '+{n} more': '+{n} nữa',

  // ── Wiki — tree context menu ────────────────────────────────────────────
  'New file…': 'Tệp mới…',
  'New folder…': 'Thư mục mới…',
  'Upload file…': 'Tải tệp lên…',
  'Delete folder': 'Xoá thư mục',
  'New file': 'Tệp mới',
  'New folder': 'Thư mục mới',
  'name': 'tên',
  'Delete folder?': 'Xoá thư mục?',
  'Delete file?': 'Xoá tệp?',
  'Only empty folders can be removed.': 'Chỉ xoá được thư mục rỗng.',
  'This cannot be undone.': 'Không thể hoàn tác.',
  'Delete failed: {err}': 'Xoá thất bại: {err}',
  'Save {name}': 'Lưu {name}',
  'Saved {name}': 'Đã lưu {name}',

  // ── Wiki — sidebar ──────────────────────────────────────────────────────
  'New page': 'Trang mới',
  'Upload file': 'Tải tệp lên',
  'Folder path': 'Đường dẫn thư mục',
  '{n} pages': '{n} trang',
  '{n} folders': '{n} thư mục',
  '{n} tags': '{n} thẻ',
  'Search wiki…': 'Tìm trong Wiki…',
  'Select a document': 'Chọn một tài liệu',

  // ── Wiki — page view & dialogs ──────────────────────────────────────────
  'Markdown (with frontmatter)…': 'Markdown (kèm frontmatter)…',
  'New wiki page': 'Trang Wiki mới',
  'Path': 'Đường dẫn',
  'Content (Markdown)': 'Nội dung (Markdown)',
  'Path is required': 'Cần nhập đường dẫn',
  'History · {path}': 'Lịch sử · {path}',
  'No history': 'Chưa có lịch sử',

  // ── Diagnostics ─────────────────────────────────────────────────────────
  'Diagnostics': 'Chẩn đoán',
  'Daemon supervision & ports': 'Giám sát daemon và cổng',
  'Restart daemon': 'Khởi động lại daemon',
  'Running (supervised)': 'Đang chạy (có giám sát)',
  'Running (adopted)': 'Đang chạy (tiếp quản)',
  'External (web)': 'Bên ngoài (web)',
  'Starting…': 'Đang khởi động…',
  'Crashed': 'Đã sập',
  'Idle': 'Nghỉ',
  'since {t}': 'từ {t}',
  'free': 'trống',
  'Copy all': 'Sao chép tất cả',
  'Copied {n} log lines': 'Đã sao chép {n} dòng nhật ký',
  'No logs yet': 'Chưa có nhật ký',
};
