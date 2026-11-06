/* COMMON SCRIPT: theme, language, mobile menu. Used by every page.
   Page scripts add their own Bangla text with AR.add({key:'বাংলা'}). */
(function(){
const $=s=>document.querySelector(s),root=document.documentElement;
try{const t=localStorage.getItem('ar_theme');if(t)root.dataset.theme=t}catch(e){}
$('#themeBtn').onclick=()=>{const c=root.dataset.theme||(matchMedia('(prefers-color-scheme: dark)').matches?'dark':'light'),n=c=='dark'?'light':'dark';root.dataset.theme=n;try{localStorage.setItem('ar_theme',n)}catch(e){}};
const nodes=[...document.querySelectorAll('[data-i18n]')];nodes.forEach(n=>n._en=n.innerHTML);
let lang='en';try{lang=localStorage.getItem('ar_lang')||'en'}catch(e){}
window.AR={BN:{nav_courses:'কোর্স',
nav_demo:'ফ্রি ডেমো',
nav_features:'ফিচার',
nav_how:'কীভাবে কাজ করে',
login:'লগইন',
register:'রেজিস্টার',
tag:'ডিইউ ভর্তি প্রার্থীদের জন্য অনলাইন মডেল টেস্ট।'},
 add(d){Object.assign(this.BN,d);this.apply()},
 apply(){root.lang=lang;nodes.forEach(n=>{n.innerHTML=lang=='bn'&&this.BN[n.dataset.i18n]||n._en});$('#langBtn').textContent=lang=='bn'?'EN':'বাং'}};
$('#langBtn').onclick=()=>{lang=lang=='bn'?'en':'bn';try{localStorage.setItem('ar_lang',lang)}catch(e){}AR.apply()};
AR.apply();
const mb=$('#burger'),mn=$('#menu');mb.onclick=()=>{const o=mn.classList.toggle('open');mb.setAttribute('aria-expanded',o)};mn.onclick=e=>{if(e.target.tagName=='A'){mn.classList.remove('open');mb.setAttribute('aria-expanded',false)}};
const y=$('#yr');if(y)y.textContent=new Date().getFullYear();
})();
