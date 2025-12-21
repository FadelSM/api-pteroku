import fetch from 'node-fetch';

const REQUIRED = ['domain','plta','pltc'];

const json   = (res,obj,status=200)=> res.status(status).json(obj);
const bail   = (res,msg,status=400)=> json(res,{error:msg},status);

const getCreds = req=>{
  const u = new URL(req.url,`https://${req.headers.host}`);
  const o = {};
  for(const k of REQUIRED) o[k] = u.searchParams.get(k);
  return o;
};
const chkCreds = c=> REQUIRED.every(k=> c[k]?.trim());

const fetchPT = async (path,{method='GET',body=null,admin=false}={})=>{
  const opts = {
    method,
    headers:{
      Accept:'application/json',
      'Content-Type':'application/json',
      Authorization:`Bearer ${admin ? global.pltc : global.plta}`
    }
  };
  if(body) opts.body = JSON.stringify(body);

  const url = `${global.domain}/api/application/${path}`.replace(/\/+/g,'/');
  const res = await fetch(url,opts);

  if(!res.ok) {
    const err = await res.text();
    const e   = JSON.parse(err);
    const msg = e.errors?.[0]?.detail || e.message || `HTTP ${res.status}`;
    const out = new Error(msg);
    out.status = res.status;
    throw out;
  }
  return res.json();
};

export default async function handler(req, res){
  res.setHeader('Access-Control-Allow-Origin','*');
  res.setHeader('Access-Control-Allow-Methods','GET,POST,DELETE');
  res.setHeader('Access-Control-Allow-Headers','Content-Type');
  if(req.method==='OPTIONS') return res.status(200).end();

  try{
    const creds = getCreds(req);
    if(!chkCreds(creds)) return bail(res,'Missing query: domain, plta, pltc');

    global.domain = creds.domain.replace(/\/+$/,'');
    global.plta   = creds.plta;
    global.pltc   = creds.pltc;

    // Extract path tanpa query string
    const url = new URL(req.url, `https://${req.headers.host}`);
    const path = url.pathname;

    if(req.method==='GET' && path==='/'){
      return json(res,{
        message:'Pterodactyl Universal Proxy – Online',
        endpoints:{
          'GET  /servers':'List servers',
          'GET  /admins':'List admin',
          'POST /create':'Buat user + server',
          'POST /create-admin':'Buat admin',
          'DELETE /server/:id':'Hapus server',
          'DELETE /admin/:id':'Hapus admin'
        }
      });
    }

    if(req.method==='GET' && path==='/servers'){
      const j = await fetchPT('servers');
      return json(res, j.data || []);
    }

    if(req.method==='GET' && path==='/admins'){
      const j  = await fetchPT('users',{admin:true});
      const ad = (j.data||[])
        .filter(x=> x.attributes?.root_admin)
        .map(x=>({id:x.attributes.id,username:x.attributes.username}));
      return json(res,ad);
    }

    if(req.method==='POST' && path==='/create'){
      const b = req.body;
      if(!b.username||!b.email||typeof b.ram!=='number')
        return bail(res,'Body: username, email, ram (number)');

      const u = b.username.trim().toLowerCase();
      const e = b.email.trim().toLowerCase();
      const p = u + Math.floor(Math.random()*10000);
      const n = u + '-server';

      const user = await fetchPT('users',{
        method:'POST',
        body:{email:e,username:u,first_name:u,last_name:'User',password:p,language:'en'}
      });
      const uid = user.attributes.id;

      const eggJ = await fetchPT('nests/5/eggs/15');
      const startup = eggJ.attributes.startup;

      const srv = await fetchPT('servers',{
        method:'POST',
        body:{
          name:n,
          user:uid,
          egg:15,
          docker_image:eggJ.attributes.docker_image,
          startup,
          environment:{INST:'npm',USER_UPLOAD:'0',AUTO_UPDATE:'0',CMD_RUN:'npm start'},
          limits:{
            memory:b.ram,
            swap:0,
            disk:b.disk||b.ram,
            io:500,
            cpu:b.cpu??100
          },
          feature_limits:{databases:5,backups:5,allocations:5},
          deploy:{locations:[1],dedicated_ip:false,port_range:[]}
        }
      });
      return json(res,{
        username:u,
        password:p,
        email:e,
        panel_url:global.domain,
        server_id:srv.attributes.id
      });
    }

    if(req.method==='POST' && path==='/create-admin'){
      const b = req.body;
      if(!b.username||!b.email) return bail(res,'Body: username, email');
      const u = b.username.trim();
      const e = b.email.trim();
      const p = u + Math.floor(Math.random()*10000);

      await fetchPT('users',{
        method:'POST',
        admin:true,
        body:{email:e,username:u,first_name:u,last_name:'Admin',password:p,language:'en',root_admin:true}
      });
      return json(res,{username:u,password:p,panel_url:global.domain});
    }

    if(req.method==='DELETE' && path.match(/^\/server\/\d+$/)){
      const id = path.split('/')[2];
      await fetchPT(`servers/${id}`,{method:'DELETE'});
      return json(res,{success:true});
    }

    if(req.method==='DELETE' && path.match(/^\/admin\/\d+$/)){
      const id = path.split('/')[2];
      await fetchPT(`users/${id}`,{method:'DELETE',admin:true});
      return json(res,{success:true});
    }

    return bail(res,'Endpoint tidak ditemukan',404);
  }catch(e){
    return bail(res,e.message,e.status||500);
  }
          }
