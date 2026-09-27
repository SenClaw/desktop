/// Vietnamese strings for Settings → Runtime, Settings → Local models, the
/// runtime-missing banner/snack shown across OCR/TTS/Whisper/Decision
/// settings and voice features, and the Local-models pointer added to
/// Settings → Embedding. English string = key. Words shared with other
/// screens ("Save", "Cancel", "Install", "Stop", "Local models"…) live in
/// their own maps and are not repeated here.
const Map<String, String> viRuntime = {
  // Runtime — Runtime Selections
  'Runtime': 'Thời gian chạy',
  'Runtime Selections': 'Lựa chọn Runtime',
  'No compatible engine installed': 'Chưa cài engine tương thích',
  'None selected': 'Chưa chọn',
  'Auto-update selected runtime packages':
      'Tự động cập nhật các Gói Mở Rộng Thời Gian Chạy đã chọn',
  'When a newer version of a selected engine is published, download and install it in the background, and switch to it once nothing is using the old one.':
      'Khi có bản mới của một engine đã chọn, tự động tải và cài ở chế độ nền, rồi '
          'chuyển sang bản mới ngay khi không còn gì dùng bản cũ.',

  // Runtime updates channel
  'Runtime updates channel': 'Kênh cập nhật Runtime',
  'Stable installs the version each engine\'s release marks stable; Beta tracks its newest published build.':
      'Ổn định cài phiên bản mà mỗi engine đánh dấu là bản ổn định; Beta bám theo '
          'bản build mới nhất được phát hành.',
  'Check for updates': 'Kiểm tra cập nhật',
  'Checked for runtime updates': 'Đã kiểm tra cập nhật runtime',
  'Stable': 'Ổn định',
  'Beta': 'Beta',

  // Running list
  'port {p}': 'cổng {p}',
  'up {m}m': 'chạy {m} phút',
  '{n} launches': '{n} lần khởi chạy',
  'Unload': 'Gỡ nạp',

  // Engines & Frameworks
  'Engines & Frameworks': 'Engine & Framework',
  'Compatible only': 'Chỉ bản tương thích',
  'All types': 'Mọi loại',
  'LLM engines': 'Engine LLM',
  'Decision': 'Quyết định',
  'Speech to text': 'Giọng nói thành văn bản',
  'Text to speech': 'Văn bản thành giọng nói',
  'No engines match this filter.': 'Không engine nào khớp bộ lọc này.',
  'Could not fetch the runtime index: {e}': 'Không tải được danh mục runtime: {e}',
  'Incompatible': 'Không tương thích',
  'Not published yet': 'Chưa phát hành',
  '✓ Latest version': '✓ Bản mới nhất',
  '{v} - Release notes ›': '{v} - Ghi chú phát hành ›',
  'Stop it and uninstall?': 'Dừng rồi gỡ cài đặt?',
  'Stop and uninstall': 'Dừng và gỡ cài đặt',
  'Uninstall {v}': 'Gỡ cài đặt {v}',
  'Install from folder or archive': 'Cài từ thư mục hoặc file nén',
  'Install from folder or archive…': 'Cài từ thư mục hoặc file nén…',
  'View logs': 'Xem log',
  'Stop running processes': 'Dừng các tiến trình đang chạy',
  'Choose a folder…': 'Chọn thư mục…',
  'Choose an archive (.tar.gz / .zip)…': 'Chọn file nén (.tar.gz / .zip)…',
  'Choose a runtime package folder': 'Chọn thư mục gói runtime',
  'Choose a runtime package archive': 'Chọn file nén gói runtime',
  'Installing from the local path…': 'Đang cài từ đường dẫn cục bộ…',
  'Logs — {id}': 'Log — {id}',

  // Local models
  'No local models yet — press Download to fetch one.':
      'Chưa có model cục bộ nào — bấm Tải xuống để lấy một model.',
  'Unload and delete?': 'Gỡ nạp rồi xoá?',
  'Unload and delete': 'Gỡ nạp rồi xoá',
  'Download a model': 'Tải một model',
  'Hugging Face repo': 'Repo Hugging Face',
  'Look up': 'Tra cứu',
  'MLX snapshot — the whole repo is downloaded.':
      'Snapshot MLX — toàn bộ repo sẽ được tải về.',
  'GGUF file': 'File GGUF',
  'Vision projector (optional)': 'Bộ chiếu thị giác (tuỳ chọn)',
  'Choose a GGUF file': 'Chọn một file GGUF',
  'vision': 'thị giác',
  'embedding': 'embedding',
  'No runtime selected for {format} — open Runtime settings ›':
      'Chưa chọn runtime cho {format} — mở Cài đặt Runtime ›',
  'Default engine settings': 'Cài đặt mặc định của engine',
  'Applied to a model when it has no override of its own. Fields left empty use the engine\'s own default.':
      'Áp dụng cho model nào không tự đặt riêng. Để trống nghĩa là dùng mặc định của engine.',
  'Default context length': 'Độ dài ngữ cảnh mặc định',
  'Temperature': 'Temperature',
  'Top K': 'Top K',
  'Top P': 'Top P',
  'Enable thinking': 'Bật chế độ suy luận (thinking)',
  'For models that support a separate reasoning pass before the answer.':
      'Dành cho model hỗ trợ một bước suy luận riêng trước khi trả lời.',

  // Embedding → Local models pointer
  'Manage in Local models': 'Quản lý trong Model cục bộ',
  'No local GGUF embedding model yet — download one from Local models.':
      'Chưa có model embedding GGUF cục bộ nào — tải một model từ Model cục bộ.',

  // Runtime-missing banner / snack (OCR, TTS, Whisper, Decision settings;
  // voice input/output)
  'No runtime is installed for this': 'Chưa cài runtime cho mục này',
  'Open Runtime settings': 'Mở Cài đặt Runtime',
};
