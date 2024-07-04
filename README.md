# devops
DevOps code snippets

## Bash Scripts
###setup-serve.sh
This is a new server setup script specifically designed for Ubuntu (or Debian-based) servers. 
This sets up
- Node.js
- MongoDB
- Redis Cache
- Nginx
- SSL with certbot
- git
- Repository cloning
- npm
- PM2

#### Note: 
- Most of these modules are optional and can be skipped (automatically skipped if already installed).

### Requirement
- Ubuntu 20.04+ (or compatible Debian OS)
- ~/.ssh/id_rsa key needs to be created for git deployment
- Set permissions as sudo chmod 600 ~/.ssh/id_rsa to restrict access
- Make sure to point your domain to the server IP for SSL to work.
