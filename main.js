(function(){
const $=s=>document.querySelector(s),$$=s=>[...document.querySelectorAll(s)];
/* theme */
const root=document.documentElement;
try{const t=localStorage.getItem('ar_theme');if(t)root.dataset.theme=t}catch(e){}
$('#themeBtn').onclick=()=>{const c=root.dataset.theme||(matchMedia('(prefers-color-scheme: dark)').matches?'dark':'light'),n=c=='dark'?'light':'dark';root.dataset.theme=n;try{localStorage.setItem('ar_theme',n)}catch(e){}};
/* language */
const BN={nav_courses:'কোর্স',nav_demo:'ফ্রি ডেমো',nav_features:'ফিচার',nav_how:'কীভাবে কাজ করে',login:'লগইন',register:'রেজিস্টার',
s2_t:'একটি পূর্ণ পরীক্ষা ফ্রি দিন',s2_p:'কেনার আগে ডেমো মডেল টেস্ট দিন, র‍্যাংক ও বিস্তারিত বিশ্লেষণ দেখুন।',s2_b:'ফ্রি ডেমো শুরু করুন',
s3_t:'জানুন আপনি ঠিক কোথায় আছেন',s3_p:'প্রতিটি পরীক্ষার পর মেধাক্রম, বিষয়ভিত্তিক র‍্যাংক ও অগ্রগতির গ্রাফ।',s3_b:'কীভাবে কাজ করে দেখুন',
explore:'কোর্সসমূহ দেখুন',explore_p:'আপনার ভর্তি পরীক্ষা বেছে নিন এবং প্রকৃত পরীক্ষার পরিবেশে অনুশীলন শুরু করুন।',
c_dua:'ফাইনাল মডেল টেস্ট, বিষয়ভিত্তিক অনুশীলন ও পূর্ববর্তী বছরের প্রশ্ন।',c_dub:'ডিইউ বি প্রার্থীদের জন্য মডেল টেস্ট ও চ্যাপ্টারভিত্তিক অনুশীলন।',c_gst:'গুচ্ছ ভর্তি পরীক্ষার জন্য পূর্ণাঙ্গ মক টেস্ট।',c_agri:'কৃষি গুচ্ছ ভর্তি পরীক্ষার জন্য অনুশীলন টেস্ট।',
c_li1:'৩০টি ফাইনাল মডেল টেস্ট',c_li2:'এমসিকিউ + লিখিত, বাংলা ও ইংরেজি',c_li3:'লাইভ র‍্যাংক ও বিশ্লেষণ',c_li4:'নির্ধারিত সময়ের মডেল টেস্ট',c_li5:'পূর্ণাঙ্গ ভর্তি মক টেস্ট',view:'ব্যাচ দেখুন',soon:'শীঘ্রই আসছে',
demo_t:'এখনও নিশ্চিত নন? ফ্রি ডেমো দিন।',demo_p:'একটি আসল মডেল টেস্ট দিন, র‍্যাংক দেখুন এবং ব্যাখ্যা পড়ুন। কোনো পেমেন্ট লাগবে না।',demo_b:'ফ্রি ডেমো শুরু করুন',
feat:'গুরুত্বের সাথে প্রস্তুতির জন্য তৈরি',feat_p:'প্রকৃত ডিইউ ভর্তি পরীক্ষার মতো অনুশীলন করুন এবং প্রতিটি চেষ্টা থেকে শিখুন।',
f1:'প্রকৃত পরীক্ষার সময়',f1p:'টাইমার, প্রশ্ন প্যালেট, রিভিউ মার্ক এবং উত্তর বাছাইয়ের সাথে সাথে সেভ।',f2:'যেকোনো সময় আবার শুরু',f2p:'ব্রাউজার বন্ধ বা ইন্টারনেট চলে গেলেও যেখানে ছিলেন সেখান থেকেই চালিয়ে যান।',
f3:'মেধাক্রম',f3p:'সবার মধ্যে সামগ্রিক ও বিষয়ভিত্তিক র‍্যাংক, ফলাফলের পর লিডারবোর্ড।',f4:'গভীর বিশ্লেষণ',f4p:'নির্ভুলতা, প্রশ্নপ্রতি সময়, শক্তি-দুর্বলতা, ব্যাখ্যা ও অগ্রগতির গ্রাফ।',
f5:'এমসিকিউ ও লিখিত',f5p:'লিখিত উত্তরের ছবি আপলোড করুন, শিক্ষকরা মূল্যায়ন করবেন।',f6:'বাংলা ও ইংরেজি',f6p:'যেকোনো সময় ভাষা বদলান। প্রশ্ন ও ব্যাখ্যা দুই ভাষাতেই।',
how:'তিন ধাপে শুরু করুন',h1:'অ্যাকাউন্ট খুলুন',h1p:'ফোন ও ইমেইল দিয়ে রেজিস্টার করুন, টার্গেট ইউনিট বেছে নিন। সাথে সাথে স্টুডেন্ট আইডি পাবেন।',
h2:'ব্যাচে যোগ দিন',h2p:'ফ্রি ডেমো দিন অথবা বিকাশ, নগদ, রকেট বা কার্ডে ব্যাচে ভর্তি হন।',h3:'পরীক্ষা দিন, র‍্যাংকে উঠুন',h3p:'নির্ধারিত পরীক্ষা দিন, বিশ্লেষণ দেখুন এবং মেধাক্রমের উন্নতি লক্ষ্য করুন।',tag:'ডিইউ ভর্তি প্রার্থীদের জন্য অনলাইন মডেল টেস্ট।'};
const nodes=$$('[data-i18n]');nodes.forEach(n=>n._en=n.innerHTML);
let lang='en';try{lang=localStorage.getItem('ar_lang')||'en'}catch(e){}
function setLang(l){lang=l;document.documentElement.lang=l;nodes.forEach(n=>{n.innerHTML=l=='bn'&&BN[n.dataset.i18n]||n._en});$('#langBtn').textContent=l=='bn'?'EN':'বাং';try{localStorage.setItem('ar_lang',l)}catch(e){}}
$('#langBtn').onclick=()=>setLang(lang=='bn'?'en':'bn');setLang(lang);
/* mobile menu */
const mb=$('#burger'),mn=$('#menu');mb.onclick=()=>{const o=mn.classList.toggle('open');mb.setAttribute('aria-expanded',o)};mn.onclick=e=>{if(e.target.tagName=='A'){mn.classList.remove('open');mb.setAttribute('aria-expanded',false)}};
/* carousel */
const tr=$('#track'),sl=$$('.slide'),dots=$('#dots');let i=0,timer;
sl.forEach((_,k)=>{const b=document.createElement('button');b.setAttribute('aria-label','Slide '+(k+1));b.onclick=()=>go(k,true);dots.appendChild(b)});
function mark(){$$('#dots button').forEach((b,k)=>b.classList.toggle('on',k==i))}
function go(k,user){i=(k+sl.length)%sl.length;tr.scrollTo({left:i*tr.clientWidth,behavior:'smooth'});mark();if(user)play()}
tr.addEventListener('scroll',()=>{const k=Math.round(tr.scrollLeft/tr.clientWidth);if(k!==i){i=k;mark()}},{passive:true});
$('#prev').onclick=()=>go(i-1,true);$('#next').onclick=()=>go(i+1,true);
function play(){clearInterval(timer);if(!matchMedia('(prefers-reduced-motion: reduce)').matches)timer=setInterval(()=>go(i+1),5000)}
tr.addEventListener('pointerdown',()=>clearInterval(timer));tr.addEventListener('pointerup',play);
tr.addEventListener('mouseenter',()=>clearInterval(timer));tr.addEventListener('mouseleave',play);
mark();play();
$('#yr').textContent=new Date().getFullYear();
})();
