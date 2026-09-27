/// Vietnamese strings for Settings → Decision (Laya). English string = key.
/// Words shared with other screens ("Save", "Cancel", "Model"…) live in their
/// own maps and are not repeated here.
const Map<String, String> viDecision = {
  // Section and intro
  'Decision (Laya)': 'Quyết định (Laya)',
  'Laya is an open "System One" model, compatible with Jev: it does not write text, it answers typed questions — choice (pick a label), score (place on a rubric), noul (how likely a statement holds) — with probabilities. It runs inside the daemon on ONNX Runtime (CPU); a loaded model holds about its own size in RAM. For Vietnamese, use the Multilingual model: the English one reads Vietnamese wrong and still sounds sure.':
      'Laya là model “System One” mở, tương thích Jev: không sinh chữ, chỉ trả lời câu hỏi có kiểu — '
          'choice (chọn một nhãn), score (chấm theo thang), noul (xác suất có/không) — kèm phân phối xác '
          'suất. Chạy trong daemon bằng ONNX Runtime trên CPU; model đã nạp chiếm RAM cỡ dung lượng của nó. '
          'Nội dung tiếng Việt nên dùng bản Đa ngữ: bản English đọc tiếng Việt sai mà vẫn tự tin.',
  'The daemon was built without the decision-laya feature: models can still be downloaded, imported and deleted, but not loaded or asked. Rebuild with --features decision-laya (it is in DAEMON_FEATURES).':
      'Daemon được build không kèm feature decision-laya: vẫn tải / nhập / xoá model được, nhưng không '
          'nạp và không hỏi được. Build lại với --features decision-laya (đã có trong DAEMON_FEATURES).',
  'This build has no Laya engine': 'Bản build này không có engine Laya',

  // How it runs
  'How it runs': 'Cách chạy',
  'Answer with, by default': 'Mặc định trả lời bằng',
  'Applies to every request that does not choose; Try it below can still pick either.':
      'Áp dụng cho mọi lượt hỏi không tự chỉ định; ô Thử hỏi bên dưới vẫn chọn riêng được.',
  'On this machine': 'Trên máy',
  'Online backend': 'Online',
  'On this machine — Laya': 'Trên máy — Laya',
  'Online — Jev API': 'Online — Jev API',
  'in use': 'đang dùng',
  'Saved how decisions run': 'Đã lưu cách chạy',
  '{id} is not installed — install it, or pick another model.':
      '{id} chưa được cài — cài nó trước, hoặc chọn model khác.',
  'Requests that name no model use this one. "Pick by language" = the Multilingual model for text with diacritics, English for plain ASCII.':
      'Lượt hỏi không nêu model sẽ dùng model này. “Tự chọn theo ngôn ngữ” = bản Đa ngữ cho chữ có dấu, '
          'English cho chữ ASCII.',
  'CPU threads': 'Số luồng CPU',
  'automatic ({n})': 'tự động ({n})',
  'ONNX Runtime threads per model. Empty = automatic ({n} on this machine). A loaded model keeps the count it was loaded with — unload and load it again to change it.':
      'Số luồng ONNX Runtime cho mỗi model. Để trống = tự động ({n} trên máy này). Model đang nạp giữ số '
          'luồng lúc nạp — gỡ rồi nạp lại để đổi.',
  'Load on demand': 'Tự nạp khi cần',
  'On: a request that needs a model not in RAM loads it (that request takes a few seconds longer). Off: press Load first.':
      'Bật: lượt hỏi cần một model chưa nạp sẽ tự nạp nó (lượt đó lâu thêm vài giây). Tắt: phải bấm Nạp '
          'trước.',
  'Unload from RAM when unused for': 'Tự gỡ khỏi RAM khi không dùng trong',
  'A model no request has used for this long is unloaded to give the memory back (1.2–1.7 GB each). With Load on demand on, the next request loads it again.':
      'Model không được hỏi trong khoảng này sẽ được gỡ để trả bộ nhớ (mỗi model 1,2–1,7 GB). Bật Tự nạp '
          'khi cần thì lượt hỏi sau tự nạp lại.',
  '{n} minutes': '{n} phút',
  '{n} hour': '{n} giờ',
  '{n} hours': '{n} giờ',
  'TypeSafe Jev (api.typesafe.ai)': 'TypeSafe Jev (api.typesafe.ai)',
  'Cloudflare Workers AI (typesafe/jev)': 'Cloudflare Workers AI (typesafe/jev)',
  'Custom — any /v1/systemone URL': 'Tuỳ chỉnh — URL /v1/systemone bất kỳ',
  'An endpoint speaking /v1/systemone — LiteLLM, laya-serve, OpenJev…':
      'Endpoint nói giao thức /v1/systemone — LiteLLM, laya-serve, OpenJev…',
  'Cloudflare account id': 'Cloudflare account id',
  'The saved key is deleted when you press Save.': 'Key đã lưu sẽ bị xoá khi bấm Lưu.',
  'The saved key belongs to another provider or URL and is not sent here — enter a key for this choice.':
      'Key đã lưu thuộc nhà cung cấp hoặc URL khác và không được gửi tới đây — nhập key cho lựa chọn này.',
  'This model reads English only: text with accented letters still goes to the Multilingual model (when installed).':
      'Model này chỉ đọc tiếng Anh: câu có chữ có dấu vẫn được chuyển sang bản Đa ngữ (nếu đã cài).',
  'A key is saved (it is never shown again). Leave empty to keep it.':
      'Đã lưu một key (không hiển thị lại). Để trống để giữ nguyên.',
  'Optional for a custom endpoint.': 'Không bắt buộc với endpoint tuỳ chỉnh.',
  'Required.': 'Bắt buộc.',
  '•••••••• (saved)': '•••••••• (đã lưu)',
  'paste the key here': 'dán key vào đây',
  'Keep key': 'Giữ key',
  'Delete key': 'Xoá key',
  'no model sent': 'không gửi model',
  'Empty = the provider default (a pinned version, not a moving alias).':
      'Để trống = mặc định của nhà cung cấp (bản ghim, không dùng alias trôi).',
  'Timeout (seconds)': 'Thời gian chờ (giây)',
  'Online sends content off this machine': 'Chế độ online gửi nội dung ra ngoài',
  'The state and questions of every request go to the chosen provider. For data that must not leave this machine, use On this machine.':
      'State và câu hỏi của mỗi lượt được gửi tới nhà cung cấp đã chọn. Dữ liệu không được rời máy thì '
          'dùng Trên máy.',
  'Test connection': 'Thử kết nối',
  'sends one very short yes/no question, with the settings as edited (no need to Save)':
      'gửi một câu hỏi có/không rất ngắn, dùng cài đặt đang sửa (chưa cần Lưu)',
  'Connected: {model} answered in {ms} ms.': 'Kết nối được: {model} trả lời trong {ms} ms.',

  // Models
  'Models': 'Model',
  'Stored in {path}': 'Thư mục lưu: {path}',
  'checking sha256': 'đang kiểm sha256',
  'copying': 'đang sao chép',
  'listing files': 'đang lấy danh sách file',
  'downloading': 'đang tải',
  'Loading into RAM…': 'Đang nạp vào RAM…',
  'Loaded': 'Đã nạp',
  'on demand': 'tự nạp',
  'A request loaded it on demand, not the Load button.': 'Được một lượt hỏi nạp tự động, không phải bấm Nạp.',
  'loaded in {s} s · {threads} threads · {batch} · {n} asks':
      'nạp trong {s} s · {threads} luồng · {batch} · {n} lượt hỏi',
  'fixed batch of 1': 'batch cố định 1',
  'dynamic batch': 'batch động',
  'unloading soon for lack of use': 'sắp tự gỡ vì không dùng',
  'unloads in ~{n} min if unused': 'tự gỡ sau ~{n} phút nếu không dùng',
  'Error: {e}': 'Lỗi: {e}',
  'Cancelled — press Download to resume': 'Đã huỷ — bấm Tải về để tải tiếp',
  'Unload from RAM': 'Gỡ khỏi RAM',
  'Multilingual': 'Đa ngữ',
  'default': 'mặc định',
  'from folder {path}': 'từ thư mục {path}',
  'Loaded {name} in {s} s': 'Đã nạp {name} trong {s} s',
  'Unloaded {name} from RAM': 'Đã gỡ {name} khỏi RAM',
  'Downloading {name}': 'Đang tải {name}',
  'Delete {name}?': 'Xoá {name}?',
  'It is unloaded from RAM first, then its files are deleted.': 'Model sẽ được gỡ khỏi RAM trước, rồi xoá file.',
  'Its files are deleted from disk.': 'File trên đĩa sẽ bị xoá.',
  'Deleted {name}': 'Đã xoá {name}',
  'Deleted {name}; the default model is back to Pick by language':
      'Đã xoá {name}; model mặc định trở về Tự chọn theo ngôn ngữ',

  // Import / custom download
  'Import from a folder': 'Nhập từ thư mục có sẵn',
  'For an export already on this Mac (for instance one made with the laya Python package). The folder needs the ONNX graph (laya.onnx or onnx/model.onnx), the head config (rl_agent_config.json or laya_config.json) and tokenizer/. On the same APFS volume the copy is a clone: instant, no extra disk.':
      'Dùng khi đã có một bản export Laya trên máy (ví dụ từ gói laya Python). Thư mục phải có đồ thị ONNX '
          '(laya.onnx hoặc onnx/model.onnx), file config (rl_agent_config.json hoặc laya_config.json) và '
          'tokenizer/. Cùng ổ APFS thì bản sao là clone: tức thì, không tốn thêm đĩa.',
  'Choose a Laya export folder': 'Chọn thư mục export Laya',
  'Choose…': 'Chọn…',
  'id (default: folder name)': 'id (mặc định: tên thư mục)',
  'An id uses letters, digits, . _ - only': 'id chỉ gồm chữ, số, . _ -',
  'Importing {id}': 'Đang nhập {id}',
  'Download from another Hugging Face repo': 'Tải từ repo Hugging Face khác',
  'Any export with the graph, the head config and the tokenizer in the Laya layout. A branch or tag is pinned to its commit when the download starts; LFS files are checked against their sha256.':
      'Mọi bản export có đồ thị, config và tokenizer theo bố cục của Laya đều dùng được. Branch hoặc tag '
          'được ghim vào commit lúc bắt đầu tải; file LFS được kiểm sha256.',
  'Repo': 'Repo',
  'org/name or a huggingface.co URL': 'org/name hoặc URL huggingface.co',
  'Revision': 'Revision',
  'Give an id (letters, digits, . _ -) and a repo': 'Nhập id (chữ, số, . _ -) và repo',

  // Try it
  'Try it': 'Thử hỏi',
  'Answer with': 'Trả lời bằng',
  'As in settings ({backend})': 'Theo cài đặt ({backend})',
  'Default ({id})': 'Mặc định ({id})',
  'Pick by language': 'Tự chọn theo ngôn ngữ',
  '{name} · loaded': '{name} · đã nạp',
  '{name} · loads on demand': '{name} · tự nạp',
  'No API key for online': 'Chưa có API key cho online',
  'Enter the key under How it runs → Online backend, then Save.': 'Nhập key ở Cách chạy → Online rồi bấm Lưu.',
  'No model is installed': 'Chưa cài model nào',
  'Download or import a model above, or switch to Online.': 'Tải hoặc nhập một model ở trên, hoặc chuyển sang Online.',
  'No model is loaded yet — the first request loads one (a few seconds).':
      'Chưa nạp model nào — lượt hỏi đầu sẽ tự nạp (vài giây).',
  'No model is loaded': 'Chưa có model nào được nạp',
  'Press Load in the list above, or turn on Load on demand in How it runs.':
      'Bấm Nạp ở danh sách trên, hoặc bật Tự nạp khi cần ở Cách chạy.',
  'Sample': 'Mẫu',
  'State': 'State',
  'Plain text, or JSON (an object, or an array of conversation turns)':
      'Chữ thường, hoặc JSON (object, hoặc mảng các lượt hội thoại)',
  'Questions': 'Câu hỏi',
  'JSON: id → { type, instructions, criteria?, labels? }': 'JSON: id → { type, instructions, criteria?, labels? }',
  'The questions are not valid JSON: {e}': 'Ô câu hỏi không phải JSON hợp lệ: {e}',
  'routing: {reason}': 'định tuyến: {reason}',
  '{n} input tokens': '{n} token đầu vào',
  '{n} graph runs': '{n} lượt chạy đồ thị',
  'score {s} on a 0–{max} scale': 'điểm {s} trên thang 0–{max}',
  'yes': 'có',
  'P(holds)': 'P(đúng)',
  'How concentrated the distribution is (1 − normalised entropy). Laya says plainly this is NOT a calibrated probability.':
      'Độ tập trung của phân phối (1 − entropy chuẩn hoá). Laya nói rõ đây KHÔNG phải xác suất đã hiệu chỉnh.',
  "max(p) — the quantity Laya's temperature scaling calibrates: of answers at this level, about that share are right.":
      'max(p) — đại lượng mà temperature scaling của Laya hiệu chỉnh: trong các câu trả lời có mức này, '
          'khoảng chừng đó là đúng.',
  'P(act) from the act/escalate head: whether the model thinks this answer should be acted on (high) or handed to a person (low).':
      'P(hành động) từ đầu act/escalate: model nghĩ nên làm theo câu trả lời này (cao) hay chuyển cho người '
          '(thấp).',
  'Vietnamese email — category, spam, phishing': 'Email tiếng Việt — phân loại, spam, phishing',
  'Vietnamese call-centre conversation': 'Hội thoại tổng đài tiếng Việt',
  'Support ticket (English) — laya.triage_questions()': 'Ticket hỗ trợ (English) — laya.triage_questions()',
  'Prompt guard (English) — laya.guard_questions()': 'Chặn prompt độc (English) — laya.guard_questions()',

  // Tool-call gate
  'Tool-call gate': 'Cổng tool call',
  'Tool-call gate — agent shell commands': 'Cổng tool call — lệnh shell của agent',
  'Before an agent asks you to approve a Bash command, the decision engine above (Laya on this machine or Jev online) is asked what the command does. Commands on the danger list (sudo, rm -rf, git push, deploys, secret files, command substitution…) are never sent and always ask — the list, not the threshold, is the safety boundary. The gate can only save a prompt, never refuse; an error or more than {s} s still asks.':
      'Trước khi agent xin bạn duyệt một lệnh Bash, bộ quyết định ở trên (Laya trên máy hoặc Jev online) được hỏi lệnh đó '
          'làm gì. Lệnh khớp danh sách nguy hiểm (sudo, rm -rf, git push, deploy, file bí mật, thay thế lệnh…) không bao giờ '
          'được gửi đi và luôn hỏi — danh sách, không phải ngưỡng, mới là ranh giới an toàn. Cổng chỉ có thể bỏ bớt một lần '
          'hỏi, không bao giờ tự từ chối; lỗi hay quá {s} s thì vẫn hỏi.',
  'Shadow': 'Chạy bóng',
  'Threshold to run': 'Ngưỡng cho chạy',
  'By backend (now: {set})': 'Theo backend (đang là: {set})',
  'Laya: what does this command do (one choice of 8)': 'Laya: lệnh này làm gì (1 câu chọn 8 nhóm)',
  'Cookbook: the reversible yes/no question (suits Jev)': 'Cookbook: câu reversible đúng/sai (hợp Jev)',
  'The decision engine is not asked; every command that needs approval prompts as before.':
      'Không hỏi bộ quyết định; mọi lệnh cần duyệt vẫn hiện thẻ hỏi như cũ.',
  'Asks the decision engine and records what it would do, but still shows the prompt — to compare it with your answers before trusting it.':
      'Hỏi bộ quyết định và ghi lại nó định làm gì, nhưng vẫn hiện thẻ hỏi — để so với câu trả lời của bạn trước khi tin '
          'nó.',
  'A command scored as surely reading, testing or editing (at or above the threshold) runs once without a prompt. Every other command still asks.':
      'Lệnh được chấm chắc chắn chỉ đọc / chạy test / sửa file (≥ ngưỡng) chạy luôn, một lần, không hỏi. Mọi lệnh khác vẫn '
          'hỏi.',
  'Laya: P(can be undone) = P(read) + P(run tests) + P(edit files in the project).':
      'Laya: xác suất hoàn tác được = P(đọc) + P(chạy test) + P(sửa file trong dự án).',
  'Cookbook: P(true) of "only reads or changes files in the project and can be undone". Laya on this machine answers it very poorly — it suits Jev online.':
      'Cookbook: xác suất đúng của câu “chỉ đọc hoặc sửa file trong dự án, hoàn tác được”. Laya trên máy trả lời câu này '
          'rất kém — hợp với Jev online.',
  'Saved the tool-call gate': 'Đã lưu cổng tool call',
  'Judged {n}': 'Đã xét {n}',
  'would run {n}': 'sẽ cho chạy {n}',
  'prompts skipped {n}': 'đã bỏ qua thẻ hỏi {n}',
  'danger list {n}': 'danh sách nguy hiểm {n}',
  'errors {n}': 'lỗi {n}',
  'Of the commands the gate would have run while the prompt still showed, how you answered.':
      'Trong các lệnh cổng định cho chạy mà thẻ hỏi vẫn hiện (chạy bóng), bạn đã trả lời thế nào.',
  'gate runs / you approved {a} · you refused {r}': 'cổng cho chạy / bạn duyệt {a} · bạn từ chối {r}',
  '{n} command(s) the gate would have run were refused by you — review them before turning it on, or raise the threshold.':
      'Có {n} lệnh cổng định cho chạy mà bạn đã từ chối — xem lại trước khi bật, hoặc nâng ngưỡng.',
  'No command has gone through the gate yet — turn on Shadow to start recording.':
      'Chưa có lệnh nào qua cổng — bật Chạy bóng để bắt đầu ghi.',
  'danger list': 'danh sách nguy hiểm',
  'error → ask': 'lỗi → hỏi',
  'ran without asking': 'đã cho chạy',
  'would run': 'sẽ cho chạy',
  'asks you': 'hỏi người',
  'you approved': 'bạn duyệt',
  'you refused': 'bạn từ chối',
  'other answer': 'trả lời khác',
  'Try a command': 'Thử một lệnh',
  'Run the {n} sample commands': 'Chạy bộ {n} lệnh mẫu',
  'Uses the threshold and questions as edited (no need to Save); nothing is logged and nobody is asked.':
      'Dùng ngưỡng và bộ câu hỏi đang chỉnh (chưa cần Lưu); không ghi vào nhật ký và không hỏi ai.',
  'Request and answer (JSON)': 'Yêu cầu và câu trả lời (JSON)',
  '{a} would run · {r} held by the danger list · {e} errors':
      '{a} lệnh sẽ được cho chạy · {r} bị danh sách nguy hiểm giữ lại · {e} lỗi',

  // Pre-skill router
  'Skill before the turn': 'Chọn skill trước lượt',
  'Skill before the turn (pre-skill)': 'Chọn skill trước lượt (pre-skill)',
  'Before each chat turn SenClaw guesses which skill fits the request. The old way reads only triggers and when-to-use; the new way also reads the quoted examples in each description, then asks the decision engine (Laya / Jev) to choose among {n} candidates. A skill is loaded outright only when the keywords and the decision engine agree, or a whole trigger matched and the choice is in the top three; otherwise it is only hinted. On 32 real requests with 224 skills: the old way loaded a wrong skill 10 times, the new way 2.':
      'Trước mỗi lượt chat, SenClaw đoán skill nào hợp với câu hỏi. Cách cũ chỉ đọc triggers và when-to-use; cách mới đọc '
          'thêm các câu mẫu trong ngoặc kép ở description, rồi hỏi bộ quyết định (Laya / Jev) chọn trong {n} ứng viên. Chỉ '
          'nạp thẳng skill khi từ khoá và bộ quyết định cùng chọn, hoặc khớp nguyên một câu trigger và lựa chọn nằm trong '
          'top-3; còn lại chỉ gợi ý. Đo trên 32 câu thật với 224 skill: cách cũ nạp sai 10 lần, cách mới nạp sai 2 lần.',
  'The old way, nothing recorded.': 'Dùng cách cũ, không ghi gì.',
  'The old way still decides; the new one runs in the background and is recorded to compare — no turn is slowed.':
      'Vẫn dùng cách cũ; cách mới chạy nền và ghi lại để so — không làm chậm lượt nào.',
  'The new way decides (waits for the decision engine at most {ms} ms; past that it loads only on a whole trigger match).':
      'Dùng cách mới (chờ bộ quyết định tối đa {ms} ms; quá giờ thì chỉ nạp khi khớp nguyên câu trigger).',
  '"Pre-trigger skill" is off (Agent Behavior): both ways only hint, neither loads a skill outright.':
      '“Pre-trigger skill” đang tắt (Agent Behavior): cả cách cũ lẫn cách mới chỉ gợi ý, không nạp thẳng skill.',
  'Saved the skill routing mode': 'Đã lưu chế độ chọn skill',
  'Turns {n}': 'Đã xét {n} lượt',
  'same {n}': 'giống nhau {n}',
  'old loads {a} · new loads {b}': 'cũ nạp {a} · mới nạp {b}',
  'loads held back {n}': 'mới giữ lại {n} lần nạp',
  'engine did not answer {n}': 'bộ quyết định không trả lời {n}',
  'No turn recorded yet — turn on Shadow and chat as usual.':
      'Chưa có lượt nào được ghi — bật Chạy bóng rồi chat như thường.',
  'Try a request': 'Thử một câu',
  'Pick a skill': 'Chọn skill',
  'Old:': 'Cũ:',
  'New:': 'Mới:',
  'load': 'nạp',
  'hint': 'gợi ý',
  'no answer': 'không trả lời',
};
