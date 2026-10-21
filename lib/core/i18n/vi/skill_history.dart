/// Vietnamese strings for the skill history dialog (Plugins → Skills → History).
/// English string = key. Reused from other areas, not redefined here:
/// 'History', 'Restore', 'Restored', 'Close', 'Cancel', 'Installed', 'just now'.
const Map<String, String> viSkillHistory = {
  // ── Revision kinds ────────────────────────────────────────────────────────
  'Edited': 'Đã sửa',
  'Removed': 'Đã gỡ',
  'Changed outside SenClaw': 'Đổi ngoài SenClaw',
  'First seen': 'Thấy lần đầu',
  'current': 'hiện tại',
  'Written through SenClaw: created, overwritten or saved in the editor.':
      'Ghi qua SenClaw: tạo mới, ghi đè hoặc lưu trong trình soạn thảo.',
  'Installed from ClawHub.': 'Cài từ ClawHub.',
  'Put back to an earlier revision.': 'Đã đưa về một bản trước đó.',
  'The skill was removed. Its last content is still restorable.':
      'Skill đã bị gỡ. Nội dung cuối cùng vẫn khôi phục được.',
  'Found different on disk: a CLI install, a kit, or a text editor. Also used to keep what was there just before SenClaw overwrote it.':
      'Phát hiện khác trên đĩa: cài bằng CLI, kit hoặc trình soạn thảo. Cũng dùng để giữ lại bản có trước khi SenClaw ghi đè.',
  'The first time SenClaw saw this skill; nothing earlier is known.':
      'Lần đầu SenClaw thấy skill này; không biết gì về trước đó.',

  // ── Rows and detail ───────────────────────────────────────────────────────
  '{n} min ago': '{n} phút trước',
  '{n} h ago': '{n} giờ trước',
  '{n} days ago': '{n} ngày trước',
  'generation': 'thế hệ',
  '{n} file': '{n} tệp',
  '{n} files': '{n} tệp',
  'restored from': 'khôi phục từ',
  'CHANGE': 'THAY ĐỔI',
  'No content difference from the previous revision.':
      'Nội dung không khác bản trước.',
  'scan: {n}': 'quét: {n}',
  'Security scan: {n} findings (risk {r}/100)':
      'Quét bảo mật: {n} phát hiện (rủi ro {r}/100)',
  '{n} loads · fallback {f} · tool failures {t}':
      '{n} lần nạp · lỗi lượt {f} · tool hỏng {t}',

  // ── Shadowing ─────────────────────────────────────────────────────────────
  'overrides {what}': 'thay thế {what}',
  'the bundled skill': 'skill dựng sẵn',
  'the global skill': 'skill dùng chung',
  'Replaces {what} with the same name; that one is hidden while this exists.':
      'Thay thế {what} cùng tên; bản đó bị ẩn khi bản này còn.',
  'This skill replaces {what} with the same name.':
      'Skill này thay thế {what} cùng tên.',
  'Skills in the managed directory take precedence over bundled ones; the other one is hidden while this exists.':
      'Skill trong thư mục quản lý được ưu tiên hơn skill dựng sẵn; bản kia bị ẩn khi bản này còn.',

  // ── Restore ───────────────────────────────────────────────────────────────
  'Restore this revision?': 'Khôi phục bản này?',
  "The skill's files are put back as they were. The current content stays in the history.":
      'Các tệp của skill được đưa về như lúc đó. Nội dung hiện tại vẫn nằm trong lịch sử.',
  'Skill restored': 'Đã khôi phục skill',
  'Could not restore this revision': 'Không khôi phục được bản này',
  'Could not load the history': 'Không tải được lịch sử',
  'This is the current revision.': 'Đây là bản hiện tại.',
  'A removal has no content of its own; pick the revision before it.':
      'Bản gỡ không có nội dung riêng; hãy chọn bản ngay trước nó.',
  'This revision hit a size cap, so its content is incomplete.':
      'Bản này chạm giới hạn kích thước nên nội dung không đầy đủ.',
  'Its content was dropped: only the newest 30 revisions keep it.':
      'Nội dung đã bị bỏ: chỉ 30 bản mới nhất còn giữ.',
  'Only skills in the managed skills directory can be restored.':
      'Chỉ skill trong thư mục skill được quản lý mới khôi phục được.',
  "No history yet. A skill's history starts the first time it is changed through SenClaw or seen by the daemon.":
      'Chưa có lịch sử. Lịch sử của skill bắt đầu từ lần đầu nó được đổi qua SenClaw hoặc được daemon thấy.',
};
