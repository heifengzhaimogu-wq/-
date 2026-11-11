export const columns = {编号:'code',店面:'store',小组:'team',楼盘:'estate',房间号:'room',报价:'quote',底价:'floor'};
export function validate(input) {
  const errors=[],seen=new Set();
  const rows=input.map((raw,i)=>{
    const row={}; for(const [cn,en] of Object.entries(columns)) row[en]=raw[cn]??raw[en];
    for(const key of ['code','store','team','estate','room']) { row[key]=String(row[key]??'').trim(); if(!row[key]) errors.push(`第 ${i+2} 行：${Object.keys(columns).find(k=>columns[k]===key)}不能为空`); }
    for(const key of ['quote','floor']) { const original=row[key]; row[key]=Number(String(original??'').replace(/,/g,'')); if(original===undefined||original===null||String(original).trim()===''||!Number.isFinite(row[key])||row[key]<0||Math.abs(Math.round(row[key]*100)-row[key]*100)>0.000001) errors.push(`第 ${i+2} 行：价格须为非负数字，最多两位小数`); }
    if(row.floor>row.quote) errors.push(`第 ${i+2} 行：底价不能高于报价`);
    if(seen.has(row.code)) errors.push(`第 ${i+2} 行：房源编号 ${row.code} 重复`); seen.add(row.code); return row;
  }); if(!rows.length)errors.push('表格为空'); if(rows.length>5000)errors.push('单次最多导入 5000 条'); return {rows,errors};
}
export function diff(rows,existing){return rows.map(r=>{const old=existing.find(x=>x.code===r.code);return {...r,expected_version:old?.version??null,kind:!old?'新增':['store','team','estate','room','quote','floor'].some(k=>old[k]!==r[k])?'变更':'不变',old};});}
export const sample=Array.from({length:24},(_,i)=>({code:`QS${String(10001+i)}`,store:['天河店','珠江新城店','海珠店'][Math.floor(i/8)],team:['一组','二组'][Math.floor(i/4)%2],estate:['保利心语花园','中海花城湾','珠江帝景','万科金域华府'][i%4],room:`${[1,2,3][i%3]}栋 ${1001+i}室`,quote:4500+i*200,floor:4200+i*200,status:i%5===0?'corrected':i%3===0?'confirmed':'pending',version:1,updated_at:new Date().toISOString()}));
