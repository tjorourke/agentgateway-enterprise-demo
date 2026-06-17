"""connect.py — run from the notebook's first cell:  %run setup/scripts/connect.py
Loads setup/.env.local, puts arctl on PATH, mints a catalog token — into the
kernel's environment so the `!arctl ...` cells inherit it. Keeps the notebook
clean (no setup code on screen)."""
import os, json, urllib.request, urllib.parse, pathlib

if pathlib.Path('agentregistry-agentcore-kind/setup').is_dir():
    os.chdir('agentregistry-agentcore-kind')

def _load(p):
    if p and os.path.exists(p):
        for ln in open(p):
            ln = ln.strip()
            if ln.startswith('export '): ln = ln[7:]
            if ln and not ln.startswith('#') and '=' in ln:
                k, v = ln.split('=', 1)
                os.environ[k] = v.strip().strip('"').strip("'")

_load('setup/.env.local'); _load(os.environ.get('SECRETS_FILE', ''))
os.environ['PATH'] = os.path.expanduser('~/.arctl/bin') + os.pathsep + os.environ.get('PATH', '')
os.environ.setdefault('ARCTL_API_BASE_URL', 'http://localhost:12121')
os.environ.setdefault('CLUSTER_NAME', 'agentcore-demo')
os.environ['NO_COLOR'] = '1'; os.environ['TERM'] = 'dumb'
try:
    _d = urllib.parse.urlencode({'grant_type': 'client_credentials', 'client_id': 'admin',
                                 'scope': 'openid profile email Groups'}).encode()
    os.environ['ARCTL_API_TOKEN'] = json.load(urllib.request.urlopen(
        os.environ['ARCTL_API_BASE_URL'] + '/api/autoauth/oauth/token', _d, timeout=10))['access_token']
except Exception as e:
    print('token error:', e)
print('token:', 'ok' if os.environ.get('ARCTL_API_TOKEN') else 'MISSING',
      '| anthropic:', 'set' if os.environ.get('ANTHROPIC_API_KEY') else 'MISSING',
      '| cluster: kind-' + os.environ['CLUSTER_NAME'])
