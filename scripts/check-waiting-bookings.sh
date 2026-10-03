#!/usr/bin/env bash
# Read-only: shows bookings still waiting for a professional and who could take them.
# Prints booking/professional fields only (no emails, no credentials). Needs kubectl on aks-homeease-dev.
set -euo pipefail
kubectl exec -n "${NS:-homeease-dev}" deploy/backend -- node -e "
const m=require('mongoose');
const B=require('./models/Booking'),P=require('./models/Professional');require('./models/Service');
const {hasScheduledTimeStarted}=require('./services/booking/bookingSchedule');
(async()=>{
 await m.connect(process.env.MONGO_URI,{serverSelectionTimeoutMS:8000});
 const w=await B.find({professional:null,status:{\$in:['Assigned','Confirmed']}}).populate('service','category').lean();
 console.log('bookings waiting for a professional:',w.length);
 for(const b of w){
   const cat=(b.service&&b.service.category)||b.customCategory;
   console.log(' -',String(b._id).slice(-6),'|',cat,'|',new Date(b.date).toISOString().slice(0,10),b.timeSlot,'|',b.area,'| slot already started:',hasScheduledTimeStarted(b));
   const pros=await P.find({category:cat,active:true}).select('name status').lean();
   const free=pros.filter(p=>p.status==='Available');
   console.log('     professionals in',cat+':',pros.length,'| Available:',free.length,'|',pros.map(p=>p.name+' ('+p.status+')').join(', ')||'none');
 }
 const per={};(await P.find().select('category status').lean()).forEach(p=>{const c=per[p.category]=per[p.category]||{n:0,a:0};c.n++;if(p.status==='Available')c.a++;});
 console.log('capacity by category (available/total):',Object.entries(per).map(([k,v])=>k+' '+v.a+'/'+v.n).join(' | '));
 process.exit(0);
})().catch(e=>{console.log('ERR',e.message);process.exit(1)})" 2>&1 | grep -v MONGOOSE
