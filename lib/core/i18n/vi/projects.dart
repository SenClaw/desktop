/// Vietnamese strings for Projects: the Projects page, the project picker in
/// New Session and the Kanban dialogs, the session list's project groups, and
/// the project banks in Knowledge → Facts. English string = key. 'Project',
/// 'Projects', 'Sessions', 'Folder', 'Cancel', 'Create', 'Archive', 'Restore',
/// 'Saved', 'Facts' and the rest of the shared vocabulary are defined in the
/// other parts of this folder — do not repeat them here (the last spread wins
/// and would change every screen that uses them).
const Map<String, String> viProjects = {
  // ── Projects page: list ─────────────────────────────────────────────────
  'A folder your sessions and boards work in, with a context and facts of its own':
      'Một thư mục mà các phiên và bảng làm việc trong đó, có context và fact riêng',
  'Show archived': 'Hiện đã lưu trữ',
  'New project': 'Dự án mới',
  'No projects yet': 'Chưa có dự án nào',
  'Create a project to give sessions and boards a folder, a context and facts of their own.':
      'Tạo dự án để các phiên và bảng có thư mục, context và fact riêng.',
  'Archived projects are hidden — turn on “Show archived”.':
      'Các dự án đã lưu trữ đang bị ẩn — bật “Hiện đã lưu trữ”.',
  'Folder missing': 'Thiếu thư mục',
  'Archived': 'Đã lưu trữ',
  '{n} sessions': '{n} phiên',
  'Back to projects': 'Về danh sách dự án',

  // ── Project page ────────────────────────────────────────────────────────
  'The project folder no longer exists. Sessions cannot start in it until you point the project at a folder that does (Overview).':
      'Thư mục của dự án không còn tồn tại. Phiên không thể bắt đầu trong đó cho tới khi bạn trỏ dự án sang một thư mục có thật (tab Tổng quan).',
  'This project is archived: it takes no new sessions or boards. Restore it in Overview.':
      'Dự án này đã lưu trữ: không nhận phiên hay bảng mới. Khôi phục ở tab Tổng quan.',
  'Overview': 'Tổng quan',
  'Context': 'Context',
  'Project facts': 'Fact của dự án',
  'Boards': 'Bảng',

  // ── Create dialog ───────────────────────────────────────────────────────
  'Sessions and kanban boards of a project work in its folder, read its context, and share its facts.':
      'Phiên và bảng kanban của một dự án làm việc trong thư mục của nó, đọc context của nó và dùng chung fact của nó.',
  'Also read the agent’s common facts': 'Đọc cả fact chung của agent',
  'Off: only the project’s own facts are recalled in its chats.':
      'Tắt: trong chat của dự án chỉ nhớ lại fact riêng của dự án.',
  'Facts picked out of the project’s chats':
      'Fact rút ra từ các chat của dự án',
  'Kept in the project': 'Giữ trong dự án',
  'One bank for the project, read by all its chats and kanban workers.':
      'Một kho cho cả dự án, mọi chat và worker kanban của dự án đều đọc.',
  'Kept per chat': 'Giữ theo từng chat',
  'As outside a project. Only facts you type by hand are shared.':
      'Như ngoài dự án. Chỉ fact bạn nhập tay mới dùng chung.',
  'Not kept': 'Không giữ',
  'Nothing is extracted from the project’s chats.':
      'Không rút gì từ các chat của dự án.',

  // ── Project folder field ────────────────────────────────────────────────
  'Project folder': 'Thư mục dự án',
  'Choose the project folder': 'Chọn thư mục dự án',
  '~/work/my-project': '~/work/du-an-cua-toi',
  'Checking the folder…': 'Đang kiểm tra thư mục…',
  'The folder can be used.': 'Thư mục này dùng được.',
  'It already has a CLAUDE.md — the project context adds to it.':
      'Thư mục đã có CLAUDE.md — context của dự án sẽ bổ sung cho nó.',
  'Could not check the folder: {error}':
      'Không kiểm tra được thư mục: {error}',
  'Choose the project folder.': 'Hãy chọn thư mục dự án.',
  'The path must be absolute (start with / or ~).':
      'Đường dẫn phải là đường dẫn tuyệt đối (bắt đầu bằng / hoặc ~).',
  'That folder does not exist.': 'Thư mục đó không tồn tại.',
  'That path is not a folder.': 'Đường dẫn đó không phải thư mục.',
  'That folder cannot be read.': 'Không đọc được thư mục đó.',
  'The top of the filesystem cannot be a project folder.':
      'Thư mục gốc của hệ thống tệp không thể làm thư mục dự án.',
  'The home folder is too broad for a project; pick a folder inside it.':
      'Thư mục home quá rộng cho một dự án; hãy chọn một thư mục bên trong nó.',
  'That folder contains your home folder, which is too broad for a project.':
      'Thư mục đó chứa thư mục home của bạn, quá rộng cho một dự án.',
  "That folder holds SenClaw's own data (tokens, databases, chats).":
      'Thư mục đó chứa dữ liệu của chính SenClaw (token, cơ sở dữ liệu, các chat).',
  'The agent profiles folder cannot be a project folder.':
      'Thư mục hồ sơ agent không thể làm thư mục dự án.',
  'The folder where SenClaw keeps project contexts cannot be a project folder.':
      'Thư mục SenClaw dùng để lưu context của các dự án không thể làm thư mục dự án.',
  'Another project already uses this folder.':
      'Một dự án khác đã dùng thư mục này.',
  'The project “{name}” already uses this folder.':
      'Dự án “{name}” đã dùng thư mục này.',

  // ── Errors ──────────────────────────────────────────────────────────────
  'The daemon did not answer in time.': 'Daemon không trả lời kịp.',
  'This project no longer exists.': 'Dự án này không còn tồn tại.',
  'The context is too large (at most {kb} KB).':
      'Context quá lớn (tối đa {kb} KB).',
  'That text looks like it holds a secret ({kinds}), so it was not saved.':
      'Nội dung này có vẻ chứa bí mật ({kinds}) nên không được lưu.',
  'The date is like 2026-03 or 2026-03-02, or a range a/b.':
      'Ngày dạng 2026-03 hoặc 2026-03-02, hoặc một khoảng a/b.',
  'A fact is {min} to {max} characters long.':
      'Một fact dài từ {min} đến {max} ký tự.',

  // ── Overview tab ────────────────────────────────────────────────────────
  'A new folder applies to new sessions and to boards. A session that is already running keeps the folder it started in.':
      'Thư mục mới áp dụng cho phiên mới và cho các bảng. Phiên đang chạy giữ thư mục nó đã bắt đầu.',
  'Save changes': 'Lưu thay đổi',
  'Revert': 'Hoàn tác',
  'Project archived': 'Đã lưu trữ dự án',
  'Project restored': 'Đã khôi phục dự án',
  'Archive project': 'Lưu trữ dự án',
  'Restore project': 'Khôi phục dự án',
  'The project is archived: hidden from lists and closed to new sessions and boards. Restoring brings it back.':
      'Dự án đang được lưu trữ: bị ẩn khỏi danh sách và không nhận phiên hay bảng mới. Khôi phục để đưa nó trở lại.',
  'Hide the project and close it to new sessions and boards. Its sessions, boards, facts and context stay as they are, and you can restore it.':
      'Ẩn dự án và không nhận phiên hay bảng mới. Phiên, bảng, fact và context của nó giữ nguyên, và bạn có thể khôi phục.',
  'Delete for good': 'Xoá hẳn',
  'Removes the project, its facts and its context. Its sessions and boards stay, without the project. Nothing in the project folder is touched.':
      'Xoá dự án, fact và context của nó. Các phiên và bảng vẫn còn, nhưng không còn thuộc dự án. Không tệp nào trong thư mục dự án bị đụng tới.',
  'Delete permanently…': 'Xoá vĩnh viễn…',
  'Project deleted — {facts} facts removed, {chats} sessions detached.':
      'Đã xoá dự án — xoá {facts} fact, tách {chats} phiên.',
  'Has CLAUDE.md': 'Có CLAUDE.md',

  // ── Delete dialog ───────────────────────────────────────────────────────
  'Delete “{name}” for good?': 'Xoá hẳn “{name}”?',
  'This cannot be undone. Nothing inside the project folder is touched.':
      'Không hoàn tác được. Không tệp nào trong thư mục dự án bị đụng tới.',
  '{n} sessions leave the project and keep their history; from now on they run like any other session.':
      '{n} phiên rời dự án và giữ lịch sử; từ giờ chúng chạy như mọi phiên khác.',
  '{n} boards leave the project and keep running in the folder they ran in.':
      '{n} bảng rời dự án và vẫn chạy trong thư mục cũ của chúng.',
  '{n} facts of the project are deleted.': 'Xoá {n} fact của dự án.',
  'The project context is deleted.': 'Xoá context của dự án.',
  'Deleting a large fact bank is slow: about 23 seconds for 20,000 facts. Keep the app open until it finishes.':
      'Xoá một kho fact lớn khá chậm: khoảng 23 giây cho 20.000 fact. Hãy để ứng dụng mở cho tới khi xong.',
  'Deleting…': 'Đang xoá…',
  'Delete permanently': 'Xoá vĩnh viễn',
  'The daemon has not answered yet, but it may still be deleting. Close this and reload in a minute.':
      'Daemon chưa trả lời, nhưng có thể vẫn đang xoá. Hãy đóng hộp này và tải lại sau một phút.',

  // ── Context tab ─────────────────────────────────────────────────────────
  'Describe the project in markdown: what it is, how it is built, rules to follow. Every session of the project reads it at each turn, and so do its kanban workers. The agent cannot write here.':
      'Mô tả dự án bằng markdown: nó là gì, được xây thế nào, quy tắc cần theo. Mọi phiên của dự án đọc nó ở mỗi lượt, các worker kanban cũng vậy. Agent không thể ghi vào đây.',
  'The folder already has a CLAUDE.md, which the agent reads as well — this context adds to it.':
      'Thư mục đã có CLAUDE.md và agent cũng đọc nó — context này bổ sung thêm.',
  'The context changed elsewhere while you were editing. Saving will show both copies.':
      'Context đã đổi ở nơi khác trong lúc bạn sửa. Khi lưu sẽ hiện cả hai bản.',
  'Discard my edits and reload': 'Bỏ thay đổi của tôi và tải lại',
  '# What this project is…': '# Dự án này là gì…',
  '{n} / {max} characters': '{n} / {max} ký tự',
  'Past the limit, the end is cut when the context goes into the prompt.':
      'Quá giới hạn, phần cuối bị cắt khi context được đưa vào prompt.',
  'Getting long: it is sent at every turn, so it costs tokens each time.':
      'Đang dài: nó được gửi ở mọi lượt nên tốn token mỗi lần.',
  'Save context': 'Lưu context',
  'Saved — sessions of the project read it from their next turn.':
      'Đã lưu — các phiên của dự án đọc nó từ lượt kế tiếp.',
  'The context changed elsewhere': 'Context đã đổi ở nơi khác',
  'Someone else saved the context (or its file was edited) after you opened it. Choose which copy to keep.':
      'Có nơi khác đã lưu context (hoặc tệp của nó bị sửa) sau khi bạn mở. Hãy chọn bản muốn giữ.',
  'On the daemon now': 'Hiện trên daemon',
  'Your edit': 'Bản bạn đang sửa',
  'Keep editing': 'Tiếp tục sửa',
  'Use the daemon’s copy': 'Dùng bản của daemon',
  'Overwrite with mine': 'Ghi đè bằng bản của tôi',

  // ── Facts tab ───────────────────────────────────────────────────────────
  'Facts of this project: every session and kanban worker of the project recalls them. Add what they should always know.':
      'Fact của dự án này: mọi phiên và worker kanban của dự án đều nhớ lại chúng. Hãy thêm những gì họ luôn cần biết.',
  'Personal facts you mention in a chat of this project stay in this bank for now — they are not shared with your other chats. Put lasting facts about yourself in the agent’s profile.':
      'Hiện tại, fact cá nhân bạn nói trong một chat của dự án này nằm lại kho này — không dùng chung với các chat khác của bạn. Thông tin lâu dài về bản thân hãy đặt trong hồ sơ của agent.',
  'Chats of this project keep their own facts, so only facts typed here appear in this bank.':
      'Các chat của dự án giữ fact riêng của từng chat, nên kho này chỉ có fact nhập tay ở đây.',
  'Facts are not being kept from this project’s chats; only facts typed here appear in this bank.':
      'Không giữ fact từ các chat của dự án này; kho này chỉ có fact nhập tay ở đây.',
  'The agent’s common facts are not read in this project.':
      'Fact chung của agent không được đọc trong dự án này.',
  '{n} facts': '{n} fact',
  'A fact as a full sentence, e.g. “The API listens on port 7421.”':
      'Một fact là một câu đầy đủ, ví dụ “API lắng nghe ở cổng 7421.”',
  'About the project or the world': 'Về dự án hoặc thế giới',
  'Something the agent did': 'Điều agent đã làm',
  'When (optional): 2026-03': 'Khi nào (không bắt buộc): 2026-03',
  'Add fact': 'Thêm fact',
  'Fact added': 'Đã thêm fact',
  'That fact was already there; it is now marked as typed by hand.':
      'Fact đó đã có sẵn; giờ nó được đánh dấu là nhập tay.',
  'This project has no facts.': 'Dự án này chưa có fact nào.',
  'Typed by hand; what a conversation says never replaces it.':
      'Nhập tay; lời nói trong hội thoại không bao giờ thay được nó.',
  'typed': 'nhập tay',
  'Kept from a kanban card that a worker finished.':
      'Giữ lại từ một thẻ kanban mà worker đã hoàn thành.',

  // ── Boards and Sessions tabs ────────────────────────────────────────────
  'Kanban boards of this project. Their cards run in the project folder, with the project context.':
      'Các bảng kanban của dự án này. Thẻ của chúng chạy trong thư mục dự án, kèm context của dự án.',
  'An archived project takes no new boards.':
      'Dự án đã lưu trữ không nhận bảng mới.',
  'This project has no boards yet.': 'Dự án này chưa có bảng nào.',
  'Runs in a scratch folder': 'Chạy trong thư mục tạm',
  'Runs in {dir}': 'Chạy trong {dir}',
  '{n} cards': '{n} thẻ',
  'Sessions created in this project work in its folder. A session cannot be moved into or out of a project later.':
      'Các phiên tạo trong dự án này làm việc trong thư mục của nó. Một phiên không thể chuyển vào hay ra khỏi dự án về sau.',
  'New session here': 'Phiên mới trong dự án',
  'An archived project takes no new sessions.':
      'Dự án đã lưu trữ không nhận phiên mới.',
  'No session has been created in this project yet.':
      'Chưa có phiên nào được tạo trong dự án này.',

  // ── New Session ─────────────────────────────────────────────────────────
  'No project': 'Không có dự án',
  'The folder follows the project': 'Thư mục theo dự án',
  'In the project “{name}” — it works in the project folder.':
      'Trong dự án “{name}” — làm việc trong thư mục của dự án.',
  'The session could not be created: {error}':
      'Không tạo được phiên: {error}',

  // ── Kanban ──────────────────────────────────────────────────────────────
  'Follows the project — change it in the project.':
      'Theo dự án — muốn đổi thì đổi ở dự án.',
  'All projects': 'Tất cả dự án',
  'No board belongs to this project.': 'Không có bảng nào thuộc dự án này.',
  'Project: {name}': 'Dự án: {name}',
  'Project: {name} · Workspace: {dir}': 'Dự án: {name} · Thư mục làm việc: {dir}',

  // ── Session list ────────────────────────────────────────────────────────
  'Agents': 'Agent',
};
