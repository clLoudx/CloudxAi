function navTo(id){document.getElementById(id).scrollIntoView({behavior:'smooth'})}
function copyText(id){const t=document.getElementById(id);navigator.clipboard.writeText(t.innerText).then(()=>alert('Copied to clipboard'))}
document.addEventListener('DOMContentLoaded',()=>{});
