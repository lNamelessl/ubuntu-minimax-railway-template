// Local GraphQL helper for Railway API. Reads token from CLI config. NOT committed.
const fs = require('fs');
const path = require('path');
const cfg = JSON.parse(fs.readFileSync(path.join(process.env.USERPROFILE, '.railway', 'config.json'), 'utf8'));
const token = cfg.user?.accessToken || cfg.user?.token;
const query = process.argv[2];
const vars = process.argv[3] ? JSON.parse(process.argv[3]) : {};
(async () => {
  const res = await fetch('https://backboard.railway.com/graphql/v2', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({ query, variables: vars }),
  });
  const json = await res.json();
  console.log(JSON.stringify(json, null, 2));
})().catch(e => { console.error(e.message); process.exit(1); });
