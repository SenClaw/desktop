/// Vietnamese strings for Settings → Claude Code (the Claude Code worker,
/// its MCP bridge commands and runs) and Settings → sen-link (A2A peering,
/// invites, peers, delegated tasks). English string = key. Words shared with
/// other screens ("Save", "Cancel", "Enabled", "Refresh", "Copy"…) live in
/// their own maps and are not repeated here.
const Map<String, String> viCowork = {
  'Allowed tools':
      'Công cụ được phép',
  'Ask it to work on its own git branch (worktree)':
      'Yêu cầu làm trên nhánh git riêng (worktree)',
  'Assign a kanban card to "claude-code" and move it to Ready: Claude Code does the work, SenClaw verifies it before the card is closed.':
      'Giao thẻ kanban cho "claude-code" rồi chuyển sang Ready: Claude Code làm việc, SenClaw kiểm chứng trước khi đóng thẻ.',
  'Assignee':
      'Người nhận',
  'Binary':
      'Tệp thực thi',
  'Board for incoming tasks':
      'Bảng cho tác vụ nhận vào',
  'Chat for SenClaw tools':
      'Chat cho công cụ SenClaw',
  'Chat id (jid) whose schedule, memory and calendar tools Claude Code uses. Empty = the first chat.':
      'Mã chat (jid) mà Claude Code dùng công cụ lịch, bộ nhớ và lịch hẹn của nó. Để trống = chat đầu tiên.',
  'Connect Claude Code to SenClaw (MCP)':
      'Kết nối Claude Code với SenClaw (MCP)',
  'Connect this SenClaw to another one (A2A protocol) to hand tasks back and forth. Tasks a peer sends land on a kanban board.':
      'Kết nối SenClaw này với một SenClaw khác (giao thức A2A) để giao việc qua lại. Tác vụ peer gửi đến sẽ nằm trên một bảng kanban.',
  'Could not reach this peer':
      'Không kết nối được peer này',
  'Create invite code':
      'Tạo mã mời',
  'Default assignee':
      'Người nhận mặc định',
  'Empty = your Claude Code default.':
      'Để trống = mặc định của Claude Code.',
  'Enable sen-link and save first.':
      'Hãy bật sen-link và lưu trước.',
  'Fix rounds':
      'Số vòng sửa',
  'Found':
      'Đã tìm thấy',
  'How peers reach this daemon, e.g. a Tailscale address. The daemon must be bound beyond loopback (Settings → General → Network access).':
      'Địa chỉ peer dùng để gọi daemon này, ví dụ địa chỉ Tailscale. Daemon phải được mở ra ngoài loopback (Cài đặt → Chung → Truy cập mạng).',
  'Install Claude Code and sign in by running `claude` once, or set the binary path below.':
      'Cài Claude Code và đăng nhập bằng cách chạy `claude` một lần, hoặc đặt đường dẫn tệp thực thi bên dưới.',
  'Invite code':
      'Mã mời',
  'Max turns':
      'Số lượt tối đa',
  'Must exit 0 before a card may close, e.g. cargo test or npm test. Never read from card text. Without it, and without a worktree diff to review, a finished card waits for a person.':
      'Phải thoát với mã 0 thì thẻ mới được đóng, ví dụ cargo test hoặc npm test. Không bao giờ đọc từ nội dung thẻ. Nếu không có lệnh này và không có diff worktree để review, thẻ đã xong sẽ chờ người duyệt.',
  'Name shown to peers':
      'Tên hiển thị với peer',
  'No Claude Code runs yet':
      'Chưa có lượt chạy Claude Code nào',
  'No peers yet':
      'Chưa có peer nào',
  'No tasks sent to this peer yet':
      'Chưa gửi tác vụ nào cho peer này',
  'Other SenClaw URL, e.g. http://100.64.0.3:18788':
      'URL của SenClaw kia, ví dụ http://100.64.0.3:18788',
  'Pair':
      'Ghép nối',
  'Pair with another SenClaw':
      'Ghép nối với SenClaw khác',
  'Paired with':
      'Đã ghép nối với',
  'Peers':
      'Peer',
  'Permission mode':
      'Chế độ quyền',
  'Public URL':
      'URL công khai',
  'Remove this peer?':
      'Xoá peer này?',
  'Review the diff before closing':
      'Review diff trước khi đóng',
  'Run once in a terminal. SENCLAW_TOKEN is the daemon API token from':
      'Chạy một lần trong terminal. SENCLAW_TOKEN là API token của daemon, lấy từ',
  'Run this peer\'s tasks without review?':
      'Chạy tác vụ của peer này mà không cần duyệt?',
  'SenClaw MCP servers are added automatically.':
      'Các MCP server của SenClaw được thêm tự động.',
  'Send a task to':
      'Gửi tác vụ cho',
  'Send task':
      'Gửi tác vụ',
  'Task':
      'Tác vụ',
  'Tasks':
      'Các tác vụ',
  'The worker runs as you, with the tools allowed below (Bash by default). Its git worktree protects your checkout, not the machine. Only cards you trust should reach Ready.':
      'Worker chạy với quyền của bạn, dùng các công cụ được phép bên dưới (mặc định có Bash). Worktree git chỉ bảo vệ bản checkout của bạn, không bảo vệ cả máy. Chỉ để thẻ bạn tin tưởng vào Ready.',
  'Their tasks run':
      'Tác vụ của họ chạy',
  'Verify command':
      'Lệnh kiểm chứng',
  'What should the other SenClaw do?':
      'SenClaw kia cần làm gì?',
  'Where workers for incoming tasks run.':
      'Nơi worker chạy tác vụ nhận vào.',
  'With assignee claude-code this gives the peer a shell on this machine.':
      'Với người nhận là claude-code, việc này cho peer quyền chạy shell trên máy này.',
  'Worker settings':
      'Cài đặt worker',
  'Workspace folder':
      'Thư mục làm việc',
  'triage':
      'chờ duyệt',
  'use it once on the other SenClaw':
      'dùng một lần trên SenClaw kia',
  'valid until':
      'hiệu lực đến',
  'Hub URL':
      'URL hub',
  'A SenClaw hub for peers that cannot reach each other directly (NAT). Each invite then gets its own encrypted hub channel.':
      'Hub SenClaw cho các peer không gọi trực tiếp được nhau (NAT). Khi đó mỗi lời mời có một kênh hub mã hoá riêng.',
  '…or paste a senlink: connection string (hub invite)':
      '…hoặc dán chuỗi kết nối senlink: (lời mời qua hub)',
  'Pair via hub':
      'Ghép nối qua hub',
};
