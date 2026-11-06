const root=document.documentElement,theme=document.getElementById('themeToggle'),mobile=document.getElementById('mobileTheme');
function setTheme(t){root.dataset.theme=t;const dark=t==='dark';theme.innerHTML=(dark?'☀ <span>Light mode</span>':'☾ <span>Dark mode</span>');mobile.textContent=dark?'☀':'☾';}
let initial='light';try{initial=localStorage.getItem('admirank-theme')||'light'}catch(e){}setTheme(initial);
function toggle(){const t=root.dataset.theme==='dark'?'light':'dark';setTheme(t);try{localStorage.setItem('admirank-theme',t)}catch(e){}}
theme.addEventListener('click',toggle);mobile.addEventListener('click',toggle);
const tabs=document.querySelectorAll('.tabs button'),card=document.getElementById('courseCard'),empty=document.getElementById('empty');
tabs.forEach(b=>b.addEventListener('click',()=>{tabs.forEach(t=>{t.classList.toggle('selected',t===b);t.setAttribute('aria-pressed',String(t===b))});const available=b.dataset.cat==='DU A';card.hidden=!available;empty.hidden=available;}));
document.getElementById('login').addEventListener('click',e=>{e.preventDefault();const t=document.getElementById('toast');t.textContent='Student login will be enabled when account features are connected.';t.classList.add('show');clearTimeout(window.toastTimer);window.toastTimer=setTimeout(()=>t.classList.remove('show'),3000)});
document.getElementById('year').textContent=new Date().getFullYear();
// Add the official Facebook page URL and WhatsApp number once supplied.
