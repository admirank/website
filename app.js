const sb=supabase.createClient(CFG.url,CFG.key),app=document.getElementById('app');
let U=null,R=[],timer=null;
const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const pub=p=>p?sb.storage.from('public-assets').getPublicUrl(p).data.publicUrl:'';
const dt=s=>s?new Date(s).toLocaleString():'—';
const money=c=>c.sale_price!=null?`<s class="muted">৳${c.price}</s> ৳${c.sale_price}`:`৳${c.price}`;
const go=h=>location.hash=h;
function toast(t,ok=true){const e=document.getElementById('toast');e.textContent=t;e.style.background=ok?'var(--ok)':'var(--er)';e.style.display='block';setTimeout(()=>e.style.display='none',4000)}
const ok=async(p)=>{const r=await p;if(r.error)throw r.error;return r.data};
const rpc=(n,a)=>ok(sb.rpc(n,a));
const T=async f=>{try{return await f()}catch(e){toast(e.message||String(e),false);return null}};
const load=()=>app.innerHTML='<p class="muted">Loading…</p>';
const val=id=>document.getElementById(id)?.value.trim();
const A={};window.A=A;

async function setUser(u){U=u||null;R=[];if(U){const r=await sb.from('user_roles').select('role').eq('user_id',U.id);R=(r.data||[]).map(x=>x.role)}nav()}
function nav(){const l=(h,t)=>`<a href="#${h}">${t}</a>`;
document.getElementById('nav').innerHTML=`<a href="#"><img src="${CFG.logo}" alt="AdmiRank"></a>${l('','Home')}${l('about','About')}`+
(U?(R.includes('student')?l('dashboard','Dashboard')+l('results','Results')+l('leaderboard','Leaderboard')+l('profile','Profile'):'')+
(R.includes('admin')?l('admin/overview','Admin'):'')+(R.includes('evaluator')?l('evaluator','Evaluator'):'')+`<span class="sp"></span><a href="#" onclick="A.out();return false">Log out</a>`:`<span class="sp"></span>${l('login','Log in')}`);
document.getElementById('ct').textContent=CFG.contact}
A.out=async()=>{await sb.auth.signOut();go('')};

const routes={'':home,about,login,dashboard,pay,exam,take,done,results,leaderboard,profile,admin,evaluator};
const need={dashboard:'student',pay:'student',exam:'student',take:'student',done:'student',results:'student',leaderboard:'student',profile:'student',admin:'admin',evaluator:'evaluator'};
async function route(){clearInterval(timer);const [p,a,b]=location.hash.slice(1).split('/');const f=routes[p||''];
if(!f)return app.innerHTML='<p>Page not found.</p>';
if(need[p]&&(!U||!R.includes(need[p]))){return app.innerHTML=`<div class="card">Please <a href="#login">log in</a> with ${need[p]} access. (This is a UI guard only; the database enforces real permissions.)</div>`}
load();await T(()=>f(a,b))}

/* PUBLIC */
async function home(){const now=new Date().toISOString();
const [bn,an,cs]=await Promise.all([sb.from('banners').select('*').eq('is_active',true).order('display_order'),
sb.from('announcements').select('*').eq('is_published',true).order('publish_at',{ascending:false}),
sb.from('courses').select('*,batches(id,name,batch_code,status,enrollment_end)').eq('status','published')]);
const b=(bn.data||[]).filter(x=>(!x.starts_at||x.starts_at<=now)&&(!x.expires_at||x.expires_at>now));
const a=(an.data||[]).filter(x=>(!x.publish_at||x.publish_at<=now)&&(!x.expires_at||x.expires_at>now));
app.innerHTML=`${b.length?b.map(x=>`<a href="${esc(x.target_url||'#')}"><img class="hero" src="${x.image_path?pub(x.image_path):CFG.banner}" alt="${esc(x.title)}"></a><h2>${esc(x.title)}</h2><p class="muted">${esc(x.subtitle)}</p>`).join(''):`<img class="hero" src="${CFG.banner}" alt="AdmiRank">`}
<h1>Admission exam preparation, ranked.</h1><p><a class="btn" href="#${U?'dashboard':'login'}">${U?'Go to dashboard':'Log in / Sign up'}</a></p>
${a.length?'<h2>Notices</h2>'+a.map(x=>`<div class="card"><b>${esc(x.title)}</b> <span class="muted">[${x.announcement_type}]</span><br>${esc(x.message)}</div>`).join(''):''}
<h2>Courses</h2><div class="grid">${(cs.data||[]).map(c=>`<div class="card"><img src="${c.thumbnail_path?pub(c.thumbnail_path):CFG.poster}" alt=""><h3>${esc(c.title)}</h3><p>${esc(c.description)}</p><p><b>${money(c)}</b></p>
<p class="muted">Batches: ${(c.batches||[]).filter(x=>['published','ongoing'].includes(x.status)).map(x=>esc(x.name)).join(', ')||'Enter batch info ___'}</p></div>`).join('')||'<p class="muted">No courses published yet.</p>'}</div>
<p class="muted">To join a course, log in and contact ${CFG.contact} to get enrolled, then submit your payment.</p>`}
function about(){app.innerHTML=`<div class="card"><h2>About AdmiRank</h2><p>Enter your about text ___</p><h3>Contact</h3><p>${CFG.contact}</p></div>`}

async function login(mode){mode=mode||'in';const f=(i,l,t='text')=>`<label>${l}</label><input id="${i}" type="${t}">`;
app.innerHTML=`<div class="card" style="max-width:420px;margin:auto"><div class="tabs"><a href="#login">Log in</a><a href="#login/up">Sign up</a><a href="#login/forgot">Forgot password</a></div><h2>${{in:'Log in',up:'Sign up',forgot:'Reset password'}[mode]}</h2>
${mode==='up'?f('fn','Full name')+f('ph','Phone'):''}${f('em','Email','email')}${mode!=='forgot'?f('pw','Password','password'):''}
<button onclick="A.auth('${mode}')">Continue</button><p class="muted">Admins &amp; evaluators use the same login; access is decided by your database role.</p></div>`}
A.auth=m=>T(async()=>{const email=val('em'),password=val('pw');
if(m==='in'){await ok(sb.auth.signInWithPassword({email,password}));await setUser((await sb.auth.getUser()).data.user);go(R.includes('admin')?'admin/overview':R.includes('evaluator')&&!R.includes('student')?'evaluator':'dashboard')}
else if(m==='up'){await ok(sb.auth.signUp({email,password,options:{data:{full_name:val('fn'),phone:val('ph')}}}));toast('Account created. Check your email if confirmation is required.')}
else{await ok(sb.auth.resetPasswordForEmail(email,{redirectTo:location.origin+location.pathname}));toast('Reset link sent to your email.')}});

/* STUDENT */
async function dashboard(){const [en,ex,pm,at]=await Promise.all([sb.from('enrollments').select('*,batches(name,courses(title))').eq('student_id',U.id),
sb.from('exams').select('*,batches(name)').order('start_time',{ascending:false}),sb.from('payments').select('*').eq('student_id',U.id).order('submitted_at',{ascending:false}),
sb.from('exam_attempts').select('id,exam_id,status,attempt_number').eq('student_id',U.id)]);const now=Date.now();
const live=(ex.data||[]).filter(e=>new Date(e.end_time)>now),past=(ex.data||[]).filter(e=>new Date(e.end_time)<=now);
const row=e=>{const ats=(at.data||[]).filter(a=>a.exam_id===e.id),go_=new Date(e.start_time)<=now&&new Date(e.end_time)>now;
return `<tr><td>${esc(e.title)}</td><td>${esc(e.batches?.name)}</td><td>${dt(e.start_time)}</td><td>${e.duration_minutes} min</td><td>${ats.map(a=>a.status).join(', ')||'—'}</td><td>${go_?`<a class="btn" href="#exam/${e.id}">Open</a>`:''}</td></tr>`};
app.innerHTML=`<h2>My enrollments</h2>${(en.data||[]).map(e=>`<div class="card">${esc(e.batches?.courses?.title)} — ${esc(e.batches?.name)} · <b>${e.status}</b> ${e.status==='pending'?`<a class="btn" href="#pay/${e.id}">Submit payment</a>`:''}</div>`).join('')||`<div class="card muted">No enrollments yet. Contact ${CFG.contact} to be enrolled in a batch.</div>`}
<h2>Upcoming / live exams</h2><div class="card tw"><table>${live.map(row).join('')||'<tr><td class="muted">None</td></tr>'}</table></div>
<h2>Past exams</h2><div class="card tw"><table>${past.map(row).join('')||'<tr><td class="muted">None</td></tr>'}</table></div>
<h2>Payments</h2><div class="card tw"><table><tr><th>Amount</th><th>Method</th><th>Txn</th><th>Status</th><th>Note</th></tr>${(pm.data||[]).map(p=>`<tr><td>৳${p.amount}</td><td>${p.payment_method}</td><td>${esc(p.transaction_id)}</td><td>${p.status}</td><td>${esc(p.rejection_reason||'')}</td></tr>`).join('')}</table></div>`}
async function pay(id){app.innerHTML=`<div class="card" style="max-width:460px"><h2>Submit payment</h2><p>Send the course fee to: <b>${CFG.payNumber}</b></p><p class="muted">The amount is calculated by the server. Never share PINs, OTPs or passwords. Your enrollment activates only after admin verification.</p>
<label>Method</label><select id="pm"><option>bKash</option><option>Nagad</option><option>Rocket</option></select><label>Transaction ID</label><input id="tx"><label>Last 2 digits of sender phone</label><input id="l2" maxlength="2">
<button onclick="A.pay('${id}')">Submit</button></div>`}
A.pay=id=>T(async()=>{await rpc('submit_course_payment',{p_enrollment_id:id,p_payment_method:val('pm'),p_transaction_id:val('tx'),p_sender_phone_last2:val('l2')});toast('Submitted. Awaiting admin verification.');go('dashboard')});
async function exam(id){const e=(await ok(sb.from('exams').select('*').eq('id',id).single()));
app.innerHTML=`<div class="card"><h2>${esc(e.title)}</h2><p>${esc(e.description)}</p><p>Duration: ${e.duration_minutes} min · Marks: ${e.total_marks} · Max attempts: ${e.max_attempts}</p><h3>Instructions</h3><p>${esc(e.instructions)||'Enter instructions ___'}</p>
${e.warn_on_tab_switch?'<p><b>Tab switches are monitored.</b></p>':''}<button onclick="A.start('${id}',${e.require_fullscreen})">Start / Resume exam</button></div>`}
A.start=(id,fs)=>T(async()=>{const r=await rpc('start_exam',{p_exam_id:id});if(fs)document.documentElement.requestFullscreen?.().catch(()=>{});go('take/'+r.attempt_id)});
let EX={};
async function take(aid){const d=await rpc('load_exam_questions',{p_attempt_id:aid});EX={aid,d,ex:await sb.from('exams').select('prevent_copy_paste,log_tab_switches').eq('id',d.exam_id).single().then(r=>r.data||{})};
const off=new Date(d.server_time)-Date.now();
const log=(t,x)=>{if(EX.ex.log_tab_switches)sb.from('exam_activity_logs').insert({attempt_id:aid,student_id:U.id,event_type:t,event_details:x||{}}).then(()=>{})};
document.onvisibilitychange=()=>log(document.hidden?'tab_switch':'tab_return');
if(EX.ex.prevent_copy_paste){['copy','paste'].forEach(n=>document['on'+n]=e=>{e.preventDefault();log(n+'_attempt')});document.oncontextmenu=e=>{e.preventDefault();log('context_menu')}}
app.innerHTML=`<div class="timer" id="tm"></div>`+d.questions.map((q,i)=>{const s=q.saved_answer||{};return `<div class="card q"><b>Q${i+1}.</b> ${esc(q.question_text)} <span class="muted">[${q.marks} marks${+q.negative_marks?`, −${q.negative_marks}`:''}]</span>
${q.question_type==='mcq'?q.options.map(o=>`<label class="opt"><input type="radio" style="width:auto" name="q${q.id}" ${s.selected_option_id===o.id?'checked':''} onchange="A.save('${q.id}','${o.id}')"> ${esc(o.option_label)}. ${esc(o.option_text)}</label>`).join(''):
`<textarea id="w${q.id}" rows="5" placeholder="Type your answer…" onblur="A.savew('${q.id}')">${esc(s.written_answer_text)}</textarea><label>Or upload a photo/PDF of your script</label><input type="file" accept="image/jpeg,image/png,image/webp,application/pdf" onchange="A.up('${q.id}',this)">${s.answer_image_path?'<p class="muted">✔ file uploaded</p>':''}`}</div>`}).join('')+`<button class="g" onclick="A.submit()">Submit exam</button>`;
const end=new Date(d.expires_at).getTime();timer=setInterval(()=>{const s=Math.floor((end-(Date.now()+off))/1000);document.getElementById('tm').textContent=s>0?`Time left: ${Math.floor(s/60)}:${String(s%60).padStart(2,'0')}`:'Time up';if(s<=0){clearInterval(timer);A.submit(true)}},1000)}
A.save=(q,o)=>T(()=>rpc('save_exam_answer',{p_attempt_id:EX.aid,p_exam_question_id:q,p_selected_option_id:o}));
A.savew=q=>{const t=val('w'+q);if(t)T(()=>rpc('save_exam_answer',{p_attempt_id:EX.aid,p_exam_question_id:q,p_written_answer_text:t}))};
A.up=(q,inp)=>T(async()=>{const f=inp.files[0];if(!f)return;const path=`student-${U.id}/attempt-${EX.aid}/${q}-${Date.now()}.${f.name.split('.').pop().toLowerCase()}`;
await ok(sb.storage.from('answer-scripts').upload(path,f,{contentType:f.type}));await rpc('save_exam_answer',{p_attempt_id:EX.aid,p_exam_question_id:q,p_written_answer_text:val('w'+q)||null,p_answer_image_path:path});toast('Uploaded')});
A.submit=auto=>T(async()=>{if(!auto&&!confirm('Submit your exam now?'))return;await rpc('submit_exam_attempt',{p_attempt_id:EX.aid});document.onvisibilitychange=null;document.oncopy=document.onpaste=document.oncontextmenu=null;go('done')});
function done(){app.innerHTML='<div class="card"><h2>Exam submitted ✔</h2><p>MCQs are graded automatically. Written answers await manual evaluation. Results appear once published.</p><a class="btn" href="#results">My results</a></div>'}
async function results(){const r=await ok(sb.from('exam_results').select('*,exams(title)').eq('student_id',U.id).order('created_at',{ascending:false}));
app.innerHTML=`<h2>My results</h2><div class="card tw"><table><tr><th>Exam</th><th>MCQ</th><th>Written</th><th>Total</th><th>Rank</th></tr>${r.map(x=>`<tr><td>${esc(x.exams?.title)}</td><td>${x.mcq_marks}</td><td>${x.written_marks}</td><td><b>${x.total_marks}</b></td><td>${x.rank_position??'—'}</td></tr>`).join('')||'<tr><td class="muted">No published results yet.</td></tr>'}</table></div>
<p class="muted">Per-question review (your answer vs correct answer) needs extra database access — see README.</p>`}
async function leaderboard(){const r=await ok(sb.from('exam_results').select('rank_position,total_marks,exams(title)').eq('student_id',U.id));
app.innerHTML=`<h2>Leaderboard</h2><div class="card">${r.map(x=>`<p>${esc(x.exams?.title)}: rank <b>${x.rank_position??'—'}</b> (${x.total_marks} marks)</p>`).join('')||'<p class="muted">No ranked results yet.</p>'}<p class="muted">Current database policy lets students see only their own rank. A public leaderboard needs a new policy/function — see README.</p></div>`}
async function profile(){const p=await ok(sb.from('profiles').select('*').eq('id',U.id).single());const f=(k,l)=>`<label>${l}</label><input id="p_${k}" value="${esc(p[k])}">`;
app.innerHTML=`<div class="card" style="max-width:480px"><h2>Profile</h2><p>Student ID: <b>${esc(p.student_id)}</b></p>${f('full_name','Full name')}${f('phone','Phone')}${f('school','School')}${f('college','College')}<button onclick="A.prof()">Save</button>
<h3>Change password</h3><input id="np" type="password" placeholder="New password"><button class="s" onclick="A.pw()">Update password</button></div>`}
A.prof=()=>T(async()=>{await ok(sb.from('profiles').update({full_name:val('p_full_name'),phone:val('p_phone'),school:val('p_school'),college:val('p_college')}).eq('id',U.id));toast('Saved')});
A.pw=()=>T(async()=>{await ok(sb.auth.updateUser({password:val('np')}));toast('Password updated')});

/* EVALUATOR */
async function evaluator(id){const as=await ok(sb.from('evaluator_assignments').select('*,exams(title)').eq('evaluator_id',U.id).eq('status','active'));
let h=`<h2>Assigned exams</h2><div class="tabs">${as.map(a=>`<a href="#evaluator/${a.exam_id}">${esc(a.exams?.title)}</a>`).join('')||'<span class="muted">None</span>'}</div>`;
if(id){const s=await ok(sb.from('student_answers').select('*,exam_questions!inner(question_text_snapshot,correct_answer_text_snapshot,marks,question_type),exam_attempts!inner(exam_id),answer_evaluations(marks_awarded,evaluation_status,feedback)').eq('exam_attempts.exam_id',id).eq('exam_questions.question_type','written'));
const urls={};for(const x of s)if(x.answer_image_path){const u=await sb.storage.from('answer-scripts').createSignedUrl(x.answer_image_path,3600);urls[x.id]=u.data?.signedUrl}
h+=s.map(x=>{const ev=x.answer_evaluations?.[0];return `<div class="card"><b>${esc(x.exam_questions.question_text_snapshot)}</b> <span class="muted">(max ${x.exam_questions.marks})</span><p>Model answer: ${esc(x.exam_questions.correct_answer_text_snapshot)||'—'}</p><p>Student: ${esc(x.written_answer_text)||'<i>no text</i>'}</p>
${urls[x.id]?`<a href="${urls[x.id]}" target="_blank">Open script</a>${/\.pdf/i.test(x.answer_image_path)?'':`<br><img src="${urls[x.id]}" style="max-width:100%">`}`:''}
${ev?`<p><b>Submitted:</b> ${ev.marks_awarded} · ${ev.evaluation_status} · ${esc(ev.feedback)}</p>`:`<input id="m${x.id}" type="number" step="0.25" min="0" max="${x.exam_questions.marks}" placeholder="Marks"><textarea id="f${x.id}" placeholder="Feedback"></textarea><button onclick="A.ev('${x.id}')">Submit evaluation</button>`}</div>`}).join('')||'<p class="muted">No written answers.</p>'}
app.innerHTML=h}
A.ev=id=>T(async()=>{await ok(sb.from('answer_evaluations').insert({student_answer_id:id,evaluator_id:U.id,marks_awarded:+val('m'+id),feedback:val('f'+id),evaluation_status:'submitted'}));toast('Submitted for admin approval');route()});

/* ADMIN — config-driven CRUD. Field spec: name:type[:opts]  t=text n=number ta=textarea sel b=bool d=datetime date f=public image j=json */
const S='status:sel:',CR={
courses:['title,slug,description:ta,thumbnail_path:f,price:n,sale_price:n,'+S+'draft|published|archived','created_by'],
batches:['course_id,name,batch_code,description:ta,start_date:date,end_date:date,enrollment_start:date,enrollment_end:date,capacity:n,'+S+'draft|published|ongoing|completed|cancelled'],
enrollments:['student_id,batch_id,'+S+'pending|active|cancelled|expired,expires_at:d'],
coupons:['code,discount_type:sel:percentage|fixed,discount_value:n,max_discount:n,min_purchase:n,usage_limit:n,per_user_limit:n,starts_at:d,expires_at:d,is_active:b'],
subjects:['name,slug,description:ta,display_order:n,is_active:b'],chapters:['subject_id,name,description:ta,display_order:n,is_active:b'],
questions:['subject_id,chapter_id,question_type:sel:mcq|written,question_text:ta,correct_answer_text:ta,explanation:ta,difficulty:sel:easy|medium|hard,default_marks:n,default_negative_marks:n,is_active:b','created_by'],
question_options:['question_id,option_label,option_text,is_correct:b,display_order:n'],
exams:['batch_id,title,description:ta,exam_type:sel:daily|weekly|final|mock,instructions:ta,start_time:d,end_time:d,duration_minutes:n,total_marks:n,'+S+'draft|published|completed|cancelled,randomize_questions:b,randomize_options:b,warn_on_tab_switch:b,log_tab_switches:b,require_fullscreen:b,prevent_copy_paste:b,device_limit:n,allow_resume:b,max_attempts:n,show_results:b,show_correct_answers:b','created_by'],
exam_questions:['exam_id,source_question_id,question_order:n,question_type:sel:mcq|written,question_text_snapshot:ta,correct_answer_text_snapshot:ta,explanation_snapshot:ta,marks:n,negative_marks:n'],
exam_question_options:['exam_question_id,source_option_id,option_label,option_text,is_correct:b,display_order:n'],
evaluator_assignments:['evaluator_id,exam_id,'+S+'active|inactive','assigned_by'],
evaluation_rubrics:['exam_question_id,title,instructions:ta,criteria:j,max_marks:n','created_by'],
exam_result_publications:['exam_id,is_published:b,show_correct_answers:b,published_at:d','published_by'],
banners:['title,subtitle,image_path:f,target_url,display_order:n,is_active:b,starts_at:d,expires_at:d','created_by'],
announcements:['title,message:ta,announcement_type:sel:general|exam|course|important,is_published:b,publish_at:d,expires_at:d','created_by'],
site_settings:['setting_key,setting_value:j,description','updated_by'],user_roles:['user_id,role:sel:student|admin|evaluator']};
const SPECIAL=['overview','payments','evaluations','results'];
async function admin(sec){sec=sec||'overview';const tabs=[...SPECIAL,...Object.keys(CR)];
let h=`<h2>Admin</h2><div class="tabs">${tabs.map(t=>`<a href="#admin/${t}" ${t===sec?'style="background:var(--p);color:#fff"':''}>${t.replace(/_/g,' ')}</a>`).join('')}</div>`;app.innerHTML=h+'<div id="ad"></div>';const box=document.getElementById('ad');
if(sec==='overview'){const c=async(t,f)=>{let q=sb.from(t).select('*',{count:'exact',head:true});if(f)q=q.eq(...f);return (await q).count??'—'};
box.innerHTML=`<div class="grid">${[['Courses',await c('courses')],['Pending payments',await c('payments',['status','pending'])],['Pending enrollments',await c('enrollments',['status','pending'])],['Exams',await c('exams')],['Evaluations to approve',await c('answer_evaluations',['evaluation_status','submitted'])]].map(x=>`<div class="card"><h1>${x[1]}</h1>${x[0]}</div>`).join('')}</div>`}
else if(sec==='payments'){const p=await ok(sb.from('payments').select('*').order('submitted_at',{ascending:false}).limit(200));
box.innerHTML=`<div class="card tw"><table><tr><th>When</th><th>Student</th><th>Amount</th><th>Method</th><th>Txn</th><th>Last2</th><th>Status</th><th></th></tr>${p.map(x=>`<tr><td>${dt(x.submitted_at)}</td><td>${x.student_id.slice(0,8)}</td><td>৳${x.amount}</td><td>${x.payment_method}</td><td>${esc(x.transaction_id)}</td><td>${x.sender_phone_last2}</td><td>${x.status}</td><td>${x.status==='pending'?`<button class="g" onclick="A.pv('${x.id}')">Verify</button> <button class="d" onclick="A.pr('${x.id}')">Reject</button>`:''}</td></tr>`).join('')}</table></div><p class="muted">Check the transaction in the real bKash/Nagad/Rocket account before verifying.</p>`}
else if(sec==='evaluations'){const e=await ok(sb.from('answer_evaluations').select('*').order('created_at',{ascending:false}).limit(200));
box.innerHTML=`<div class="card tw"><table><tr><th>When</th><th>Evaluator</th><th>Marks</th><th>Feedback</th><th>Status</th><th></th></tr>${e.map(x=>`<tr><td>${dt(x.evaluated_at||x.created_at)}</td><td>${x.evaluator_id.slice(0,8)}</td><td>${x.marks_awarded}</td><td>${esc(x.feedback)}</td><td>${x.evaluation_status}</td><td>${x.evaluation_status==='submitted'?`<button class="g" onclick="A.ap('${x.id}')">Approve</button>`:''}</td></tr>`).join('')}</table></div>`}
else if(sec==='results'){const x=await ok(sb.from('exams').select('id,title').order('start_time',{ascending:false}));
box.innerHTML=`<div class="card"><label>Exam</label><select id="rx">${x.map(e=>`<option value="${e.id}">${esc(e.title)}</option>`).join('')}</select><button onclick="A.fin()">Finalize results</button> <button class="s" onclick="A.rank()">Calculate ranks</button><p class="muted">Publish results from the “exam result publications” tab.</p></div>`}
else await crud(box,sec)}
A.pv=id=>T(async()=>{if(!confirm('Verified in the payment provider account?'))return;await rpc('admin_verify_payment',{p_payment_id:id});toast('Verified, enrollment activated');route()});
A.pr=id=>T(async()=>{const r=prompt('Rejection reason?');if(!r)return;await rpc('admin_reject_payment',{p_payment_id:id,p_rejection_reason:r});toast('Rejected');route()});
A.ap=id=>T(async()=>{await rpc('approve_answer_evaluation',{p_evaluation_id:id});toast('Approved');route()});
A.fin=()=>T(async()=>{await rpc('finalize_exam_results',{p_exam_id:val('rx')});toast('Finalized')});
A.rank=()=>T(async()=>{await rpc('calculate_exam_ranks',{p_exam_id:val('rx')});toast('Ranks calculated')});
const tz=v=>v?new Date(new Date(v)-new Date(v).getTimezoneOffset()*6e4).toISOString().slice(0,16):'';
async function crud(box,t){const [spec,auto]=CR[t],F=spec.split(',').map(s=>{const [n,ty='t',o]=s.split(':');return{n,ty,o}});
const oc=t==='site_settings'?'updated_at':'created_at';let q=sb.from(t).select('*').limit(200);if(!['user_roles'].includes(t))q=q.order(oc,{ascending:false});const rows=await ok(q);window._rows=rows;window._F=F;window._t=t;window._auto=auto;window._edit=null;
const inp=f=>`<label>${f.n}</label>`+(f.ty==='ta'||f.ty==='j'?`<textarea id="f_${f.n}" rows="3"></textarea>`:f.ty==='sel'?`<select id="f_${f.n}">${f.o.split('|').map(o=>`<option>${o}</option>`).join('')}</select>`:f.ty==='b'?`<input id="f_${f.n}" type="checkbox" style="width:auto">`:f.ty==='d'?`<input id="f_${f.n}" type="datetime-local">`:f.ty==='date'?`<input id="f_${f.n}" type="date">`:f.ty==='n'?`<input id="f_${f.n}" type="number" step="any">`:f.ty==='f'?`<input id="f_${f.n}" type="file" accept="image/jpeg,image/png,image/webp"><small id="c_${f.n}" class="muted"></small>`:`<input id="f_${f.n}">`);
const cols=['id',...F.filter(f=>!['ta','j'].includes(f.ty)).slice(0,6).map(f=>f.n)];
box.innerHTML=`<div class="card"><h3 id="ft">New ${t}</h3>${F.map(inp).join('')}<button onclick="A.sv()">Save</button> <button class="s" onclick="A.nw()">Clear</button> <button class="d" onclick="A.dl()">Delete selected</button></div>
<div class="card tw"><table><tr>${cols.map(c=>`<th>${c}</th>`).join('')}</tr>${rows.map((r,i)=>`<tr class="r" onclick="A.ed(${i})">${cols.map(c=>`<td>${esc(typeof r[c]==='object'&&r[c]?JSON.stringify(r[c]):r[c])}</td>`).join('')}</tr>`).join('')||'<tr><td class="muted">Empty</td></tr>'}</table></div>`}
A.ed=i=>{const r=_rows[i];_edit=r;document.getElementById('ft').textContent='Editing '+r.id;_F.forEach(f=>{const e=document.getElementById('f_'+f.n),v=r[f.n];if(f.ty==='b')e.checked=!!v;else if(f.ty==='f')document.getElementById('c_'+f.n).textContent=v||'';else if(f.ty==='d')e.value=tz(v);else if(f.ty==='date')e.value=(v||'').slice(0,10);else if(f.ty==='j')e.value=v==null?'':JSON.stringify(v,null,1);else e.value=v??''});scrollTo(0,0)};
A.nw=()=>admin(_t);
A.sv=()=>T(async()=>{const o={};for(const f of _F){const e=document.getElementById('f_'+f.n);let v;
if(f.ty==='b')v=e.checked;else if(f.ty==='f'){if(e.files[0]){const fl=e.files[0],p=`${_t}/${Date.now()}-${fl.name.replace(/[^\w.-]/g,'_')}`;await ok(sb.storage.from('public-assets').upload(p,fl,{contentType:fl.type}));v=p}else if(_edit)continue;else v=null}
else{v=e.value.trim();if(v==='')v=null;else if(f.ty==='n')v=+v;else if(f.ty==='d')v=new Date(v).toISOString();else if(f.ty==='j')v=JSON.parse(v)}
if(v===null&&!_edit)continue;o[f.n]=v}
if(_edit)await ok(sb.from(_t).update(o).eq('id',_edit.id));else{if(_auto)o[_auto]=U.id;await ok(sb.from(_t).insert(o))}toast('Saved');admin(_t)});
A.dl=()=>T(async()=>{if(!_edit||!confirm('Delete selected record?'))return;await ok(sb.from(_t).delete().eq('id',_edit.id));toast('Deleted');admin(_t)});

sb.auth.onAuthStateChange((ev,s)=>setTimeout(async()=>{await setUser(s?.user);if(ev==='PASSWORD_RECOVERY'){go('profile')}}));
(async()=>{const {data}=await sb.auth.getSession();await setUser(data.session?.user);window.onhashchange=route;route()})();
