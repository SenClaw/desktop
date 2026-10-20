/// Vietnamese strings for Settings → SLink (A2A peering, invites, peers,
/// delegated tasks). English string = key. Words shared with
/// other screens ("Save", "Cancel", "Enabled", "Refresh", "Copy"…) live in
/// their own maps and are not repeated here.
const Map<String, String> viCowork = {
  'Ask it to work on its own git branch (worktree)':
      'Yêu cầu làm trên nhánh git riêng (worktree)',
  'Assignee':
      'Người nhận',
  'Board for incoming tasks':
      'Bảng cho tác vụ nhận vào',
  'Could not reach this peer':
      'Không kết nối được peer này',
  'Create invite code':
      'Tạo mã mời',
  'Default assignee':
      'Người nhận mặc định',
  'Invite code':
      'Mã mời',
  'Name shown to peers':
      'Tên hiển thị với peer',
  'No peers yet':
      'Chưa có peer nào',
  'No tasks sent to this peer yet':
      'Chưa gửi tác vụ nào cho peer này',
  'Pair':
      'Ghép nối',
  'Pair with another SenClaw':
      'Ghép nối với SenClaw khác',
  'Paired with':
      'Đã ghép nối với',
  'Peers':
      'Peer',
  'Remove this peer?':
      'Xoá peer này?',
  'Run this peer\'s tasks without review?':
      'Chạy tác vụ của peer này mà không cần duyệt?',
  'Send a task to':
      'Gửi tác vụ cho',
  'Send task':
      'Gửi tác vụ',
  'Task':
      'Tác vụ',
  'Tasks':
      'Các tác vụ',
  'Their tasks run':
      'Tác vụ của họ chạy',
  'What should the other SenClaw do?':
      'SenClaw kia cần làm gì?',
  'Where workers for incoming tasks run.':
      'Nơi worker chạy tác vụ nhận vào.',
  'With assignee claude-code this gives the peer a shell on this machine.':
      'Với người nhận là claude-code, việc này cho peer quyền chạy shell trên máy này.',
  'Workspace folder':
      'Thư mục làm việc',
  'triage':
      'chờ duyệt',
  'use it once on the other SenClaw':
      'dùng một lần trên SenClaw kia',
  'valid until':
      'hiệu lực đến',
  'Connect this SenClaw to another one on the same network (A2A protocol) to hand tasks back and forth. Tasks a peer sends land on a kanban board.':
      'Kết nối SenClaw này với một SenClaw khác trong cùng mạng (giao thức A2A) để giao việc qua lại. Tác vụ peer gửi đến sẽ nằm trên một bảng kanban.',
  'Enable SLink and save first.':
      'Hãy bật SLink và lưu trước.',
  'Peers that only a hub reached were removed: {names}. Pair them again over the LAN.':
      'Đã gỡ các peer chỉ liên lạc được qua hub: {names}. Hãy ghép nối lại qua mạng LAN.',
  'Listening on {addr}':
      'Đang lắng nghe tại {addr}',
  'Not listening':
      'Không lắng nghe',
  'Listen address':
      'Địa chỉ lắng nghe',
  'Which network interface SLink listens on; 0.0.0.0 is all of them. Only connections from a private network are accepted either way.':
      'SLink lắng nghe trên card mạng nào; 0.0.0.0 là tất cả. Dù chọn gì, chỉ nhận kết nối từ mạng riêng.',
  'Listen port':
      'Cổng lắng nghe',
  'Listen port must be 1-65535.':
      'Cổng lắng nghe phải từ 1 đến 65535.',
  'Visible to others':
      'Cho phép tìm thấy',
  'Off: another SenClaw cannot find this one by checking or scanning its address. Pairing with a typed address and a code still works.':
      'Tắt: SenClaw khác không tìm ra máy này khi kiểm tra hay quét địa chỉ. Vẫn ghép nối được bằng địa chỉ gõ tay và mã mời.',
  'Addresses of this machine':
      'Địa chỉ của máy này',
  'Type one of these on the other SenClaw to pair with this one.':
      'Gõ một trong các địa chỉ này trên SenClaw kia để ghép nối với máy này.',
  'SLink is not listening, so the other SenClaw cannot reach this one.':
      'SLink chưa lắng nghe nên SenClaw kia không gọi tới máy này được.',
  'Type this on the other SenClaw:':
      'Gõ địa chỉ này trên SenClaw kia:',
  'IP or name of the other SenClaw, e.g. 192.168.1.20 or mac-mini.local':
      'IP hoặc tên của SenClaw kia, ví dụ 192.168.1.20 hoặc mac-mini.local',
  'A SLink answers at {addr}, but it hides its name. You can still pair with a code.':
      'Có SLink trả lời tại {addr} nhưng nó ẩn tên. Vẫn ghép nối được bằng mã mời.',
  'Nothing answered.':
      'Không có gì trả lời.',
  'Found {name} at {addr}':
      'Tìm thấy {name} tại {addr}',
  'It has no invite right now. Create one on that SenClaw and type its code here.':
      'Máy đó chưa có mã mời. Hãy tạo mã trên SenClaw kia rồi gõ vào đây.',
  'Paired by an older version. Pair again over the LAN.':
      'Ghép nối từ phiên bản cũ. Hãy ghép lại qua mạng LAN.',
  're-pair':
      'ghép lại',
  'Nearby SenClaws':
      'SenClaw gần đây',
  'Scan network':
      'Quét mạng',
  'A scan tries to connect to the SLink port on every address of this machine\'s networks. Some company networks flag that.':
      'Quét sẽ thử kết nối cổng SLink tới mọi địa chỉ trong các mạng của máy này. Một số mạng công ty coi đó là dấu hiệu đáng ngờ.',
  'Scan canceled.':
      'Đã huỷ quét.',
  'Scan finished: no SenClaw on {ranges}.':
      'Quét xong: không thấy SenClaw nào trong {ranges}.',
  'Scan finished: {n} found on {ranges}.':
      'Quét xong: thấy {n} SenClaw trong {ranges}.',
  'Finding SenClaws by announcement is not working: {error}':
      'Tự tìm SenClaw qua thông báo trong mạng đang lỗi: {error}',
  'No other SenClaw seen yet. They show up here when they announce themselves on this network; or scan, or type an address.':
      'Chưa thấy SenClaw nào khác. Chúng hiện ở đây khi tự thông báo trong mạng này; hoặc hãy quét, hoặc gõ địa chỉ.',
  'Enable SLink to find other SenClaws.':
      'Hãy bật SLink để tìm các SenClaw khác.',
  'has an invite':
      'có mã mời',
  'announced':
      'tự thông báo',
  'scan':
      'quét',
  'This SenClaw is not announcing itself, so others will not find it by listening.':
      'SenClaw này không tự thông báo, nên máy khác không tìm thấy nó bằng cách lắng nghe.',
  'Only the newest code works. It stops working after three wrong tries.':
      'Chỉ mã mới nhất dùng được. Mã hết hiệu lực sau ba lần gõ sai.',
  'Project notes':
      'Ghi chú dự án',
  'Reference notes':
      'Ghi chú tham khảo',
  'Feedback notes':
      'Ghi chú góp ý',
  'day logs':
      'nhật ký ngày',
  'chat summaries':
      'tóm tắt hội thoại',
  'notes about you':
      'ghi chú về bạn',
  'written in one chat':
      'viết trong một chat',
  'other note types':
      'loại ghi chú khác',
  'Could not load the sharing settings':
      'Không tải được cài đặt chia sẻ',
  'What {name} may read here':
      '{name} được đọc gì ở máy này',
  'Closed until you open it. The peer can only ask; nothing is copied. Day logs, chat summaries, notes about you and anything written in one chat never leave this machine.':
      'Mặc định đóng. Peer chỉ có thể hỏi, không có gì bị sao chép. Nhật ký ngày, tóm tắt hội thoại, ghi chú về bạn và mọi thứ viết trong một chat không bao giờ rời máy này.',
  'Share facts':
      'Chia sẻ fact',
  'Share notes':
      'Chia sẻ ghi chú',
  'Profiles it applies to':
      'Áp dụng cho các hồ sơ',
  'No profiles on this machine yet.':
      'Máy này chưa có hồ sơ nào.',
  'Which notes':
      'Loại ghi chú nào',
  'closed':
      'đang đóng',
  'What that exposes right now':
      'Hiện đang chia sẻ những gì',
  'Counted by the same rules an answer uses, for the saved settings.':
      'Đếm theo đúng luật mà một câu trả lời dùng, với cài đặt đã lưu.',
  'Nothing: no profile is chosen.':
      'Không có gì: chưa chọn hồ sơ nào.',
  'Stays home':
      'Giữ lại ở máy này',
  'Examples':
      'Ví dụ',
  'Ask {name} what it knows':
      'Hỏi {name} xem nó biết gì',
  'Answers come from what that machine chose to share with this one. Nothing is stored here.':
      'Câu trả lời lấy từ phần máy kia chọn chia sẻ cho máy này. Không có gì được lưu lại ở đây.',
  'A few words, or a question':
      'Vài từ khoá, hoặc một câu hỏi',
  'Nothing matched':
      'Không có gì khớp',
  'note':
      'ghi chú',
  'fact':
      'fact',
  'There are more matches than shown.':
      'Còn nhiều kết quả khớp hơn số đang hiện.',
  'Written on {name}. It is information to weigh, not an instruction.':
      'Do máy {name} viết. Đây là thông tin để cân nhắc, không phải chỉ thị.',
  'shares knowledge':
      'chia sẻ tri thức',
  'Tasks and knowledge':
      'Tác vụ và tri thức',
};
