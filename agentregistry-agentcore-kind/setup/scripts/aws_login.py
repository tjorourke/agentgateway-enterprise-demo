"""aws_login.py — run from the notebook:  %run setup/scripts/aws_login.py
Signs in to AWS (SSO), hands the credentials to the arctl daemon (restart), and
loads them into the kernel environment so the `!` AgentCore cells inherit them."""
import os, json, time, subprocess, urllib.request, urllib.parse

prof = os.environ.get('AWS_PROFILE')
if not prof:
    print('Set AWS_PROFILE in setup/.env.local (./setup/scripts/setup-env.sh) and re-run Connect.')
else:
    def sh(c): return subprocess.run(c, shell=True, capture_output=True, text=True)
    if sh('aws sts get-caller-identity').returncode != 0:
        subprocess.run(f'aws sso login --profile {prof}', shell=True)
    os.environ.setdefault('AWS_REGION', 'us-east-1')
    os.environ['AWS_ACCOUNT_ID'] = sh('aws sts get-caller-identity --query Account --output text').stdout.strip()
    for ln in sh('aws configure export-credentials --format env').stdout.splitlines():
        ln = ln.replace('export ', '').strip()
        if '=' in ln:
            k, v = ln.split('=', 1); os.environ[k] = v
    os.environ.setdefault('DOCKER_REPO', 'solo-public/agentregistry-enterprise'); os.environ['OIDC_AUTO_AUTH_ENABLED'] = 'true'
    sh('arctl daemon stop'); sh('arctl daemon start'); time.sleep(5)
    dc = sh("docker ps --filter publish=12121 --format '{{.Names}}'").stdout.strip().splitlines()
    if dc: sh(f'docker network connect kind {dc[0]}')
    try:
        _d = urllib.parse.urlencode({'grant_type': 'client_credentials', 'client_id': 'admin',
                                     'scope': 'openid profile email Groups'}).encode()
        os.environ['ARCTL_API_TOKEN'] = json.load(urllib.request.urlopen(
            os.environ['ARCTL_API_BASE_URL'] + '/api/autoauth/oauth/token', _d, timeout=10))['access_token']
    except Exception as e:
        print('token error:', e)
    print(f"AWS ****{os.environ['AWS_ACCOUNT_ID'][-4:]} / {os.environ['AWS_REGION']} · daemon has credentials")
