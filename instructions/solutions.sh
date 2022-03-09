#!/bin/zsh

# default: setup colima as backend for docker
brew install colima
brew install docker
brew install docker-compose
colima start
docker version
docker-compose version

# pull docker images in advance (saves time in exercises)
docker pull postgres:12.2
docker pull python:3.7
docker pull hawkeyesec/scanner-cli:latest

# install ansible for ansible-vault exervice
brew install ansible

# clone your fork of the repo
git clone 'git@github.com:brookingcharlie/AS101-4-workshop.git'
cd AS101-4-workshop

# run the echo web application
docker-compose up --build -d
open 'http://localhost:8000/'

# install talisman to your local repo
curl https://raw.githubusercontent.com/thoughtworks/talisman/master/install.sh > /tmp/install-talisman.sh
chmod +x /tmp/install-talisman.sh
/tmp/install-talisman.sh pre-commit

# exercise 1
docker run --rm -v "$PWD/web:/target" hawkeyesec/scanner-cli:latest

# exercise 2
echo 'awsSecretKey=c64e8c79aacf5ddb02f1274db2d973f363f4f553ab1692d8d203b4cc09692f79' > danger.pem
git add danger.pem
git commit -m 'testing talisman'
cat > .talismanrc << EOF
fileignoreconfig:
- filename: danger.pem
  checksum: b4a00883406449dd0aa55bbfe6362afc1227f4f444427d019c91ca4ff90590d7
version: ""
EOF
git commit -m 'testing talisman'
git reset --hard head^

# exercise 3: see errors in github actions
cat > .github/workflows/hawkeye.yml << EOF
name: hawkeye
on: [push, pull_request]
jobs:
  scan:
    runs-on: ubuntu-latest
    container:
      image: hawkeyesec/scanner-cli:latest
      options: -v /__w/as101-4-workshop/as101-4-workshop:/target
    steps:
      - uses: actions/checkout@v2
      - run: hawkeye scan --target web/
EOF
git add .github/workflows/hawkeye.yml
git ci -m 'test hawkeye'
git push

# exercise 3: upgrade dependencies
git co -b fixes
patch -p 1 << EOF
diff --git a/web/requirements.txt b/web/requirements.txt
index 0551698..784824e 100644
--- a/web/requirements.txt
+++ b/web/requirements.txt
@@ -1,11 +1,11 @@
-Flask==0.12
+Flask==2.0.3
 Flask-SQLAlchemy==2.1
 Flask-Script==2.0.6
-Jinja2==3.0.1
+Jinja2==3.0.3
 MarkupSafe==2.0
-SQLAlchemy==1.4.23
-Werkzeug==0.11.15
+SQLAlchemy==1.4.32
+Werkzeug==2.0.3
 gunicorn==20.1.0
 itsdangerous==0.24
-psycopg2-binary==2.9.1
+psycopg2-binary==2.9.3
 -r 'requirements-dev.txt'
EOF
git add web/requirements.txt
git ci -m 'upgrade dependencies'
git push --set-upstream origin fixes

# exercise 4: create vault file
ansible-vault encrypt --output env_secrets << EOF
POSTGRES_USER="postgres"
POSTGRES_PASSWORD="postgres"
POSTGRES_DB="postgres"
EOF
ansible-vault view env_secrets
echo asdf > /tmp/pass
ansible-vault view --vault-password-file=/tmp/pass env_secrets

# exercise 4: inject variables via docker-compose
patch -p 1 << EOF
diff --git a/docker-compose.yml b/docker-compose.yml
index f61e520..b3704ab 100644
--- a/docker-compose.yml
+++ b/docker-compose.yml
@@ -22,6 +22,6 @@ services:
       #  it is just here as we are staging the database via docker.
       #  in a prod environment this would be done differently (or not in Docker at all).
       #  🌌 these aren't the droids you are looking for 🌌
-      POSTGRES_USER: postgres
-      POSTGRES_PASSWORD: postgres
-      POSTGRES_DB: postgres
+      POSTGRES_USER: \${POSTGRES_USER}
+      POSTGRES_PASSWORD: \${POSTGRES_PASSWORD}
+      POSTGRES_DB: \${POSTGRES_DB}
EOF
set +x; export $(ansible-vault view --vault-password-file=/tmp/pass env_secrets|xargs)
docker-compose config
docker-compose rm -f
docker-compose up --build

# exercise 4: commit changes
git add env_secrets
git add docker-compose.yml
git ci -m 'inject variables via docker-compose'
cat > .talismanrc << EOF
fileignoreconfig:
- filename: docker-compose.yml
  checksum: 041cf7d5ba27c545cf1b76277d0c293431fcbe4d389b0e4025fb6182a6cbe523
- filename: env_secrets
  checksum: 244df1ababbcb844da02719cf17d1d8c180baeb1101d9d28f1a8c09b50886fd1
version: ""
EOF
git add .talismanrc
git ci -m 'inject variables via docker-compose'
git push

# exercise 4: upgrade runtime dependency
patch -p 1 << EOF
diff --git a/web/requirements.txt b/web/requirements.txt
index 784824e..b1166b9 100644
--- a/web/requirements.txt
+++ b/web/requirements.txt
@@ -6,6 +6,6 @@ MarkupSafe==2.0
 SQLAlchemy==1.4.32
 Werkzeug==2.0.3
 gunicorn==20.1.0
-itsdangerous==0.24
+itsdangerous==2.0
 psycopg2-binary==2.9.3
 -r 'requirements-dev.txt'
EOF
git add web/requirements.txt
git ci -m 'upgrade runtime dependency'
git push

# exercise 4: inject secrets in github actions
mkdir -p .github/actions/prep
cat > .github/actions/prep/action.yml << EOF
name: 'Prep'
descript: 'Prepares the environment variables'
runs:
 using: 'docker'
 image: 'Dockerfile'
EOF
cat > .github/actions/prep/Dockerfile << EOF
FROM alpine
RUN apk add --update ansible
COPY entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
EOF
cat > .github/actions/prep/entrypoint.sh << EOF
#!/bin/sh
echo \$VAULT_PASS > /vault_pass.txt
echo \$(ansible-vault view --vault-password-file=/vault_pass.txt env_secrets)|xargs -n1 >> \$GITHUB_ENV
rm /vault_pass.txt
EOF
chmod +x .github/actions/prep/entrypoint.sh
patch -p 1 << EOF
diff --git a/.github/workflows/lint_test.yml b/.github/workflows/lint_test.yml
index 4073f9b..8d3ab79 100644
--- a/.github/workflows/lint_test.yml
+++ b/.github/workflows/lint_test.yml
@@ -16,6 +16,14 @@ jobs:
     steps:
     # Checks-out your repository under \$GITHUB_WORKSPACE, so your job can access it
     - uses: actions/checkout@v2
+    - uses: ./.github/actions/prep
+      env:
+        VAULT_PASS: \${{ secrets.VAULT_PASS }}
+    - name: hide credentials from the output
+      run: |
+        echo "::add-mask::\$POSTGRES_USER"
+        echo "::add-mask::\$POSTGRES_PASSWORD"
+        echo "::add-mask::\$POSTGRES_DB"
     - name: build docker containers
       run: |
         docker-compose build
EOF
git add .github
git ci -m 'inject variables in github action'
patch -p 1 << EOF
diff --git a/.talismanrc b/.talismanrc
index 153e584..4180f0f 100644
--- a/.talismanrc
+++ b/.talismanrc
@@ -3,4 +3,8 @@ fileignoreconfig:
   checksum: 041cf7d5ba27c545cf1b76277d0c293431fcbe4d389b0e4025fb6182a6cbe523
 - filename: env_secrets
   checksum: 244df1ababbcb844da02719cf17d1d8c180baeb1101d9d28f1a8c09b50886fd1
+- filename: .github/actions/prep/entrypoint.sh
+  checksum: 5b21821762c97e9a27f4c3e44470d69eaec505e78eccbee869b63739c5567c7d
+- filename: .github/workflows/lint_test.yml
+  checksum: 7545acdfa1cac375ef64cbb8cb381167e7fff83dd4058c7c3f6448b2b813f551
 version: ""
EOF
git ci -m 'inject variables in github action'
git add .talismanrc
git push

# troubleshooting: fix error getting credentials - err: exec: "docker-credential-desktop": executable file not found in $PATH, out: ``
sed -i~ -e 's/credsStore/credStore/' ~/.docker/config.json

# optional: merge changes from upstream
git remote add upstream git@github.com:ThoughtWorksInc/AS101-4-workshop.git
git fetch upstream
git merge upstream/master

# alternative: setup lima and use its embedded containerd/nerdctl instead of the docker CLI
brew install lima
alias docker='lima nerdctl'
alias docker-compose='lima nerdctl compose'
limactl start
limactl list
docker version
docker-compose -h
