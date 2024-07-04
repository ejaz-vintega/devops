#!/bin/bash

#update os repositories
sudo apt-get update
sudo apt upgrade -y

#Check if id_rsa key has been created
if [ -f ~/.ssh/id_rsa ]; then
    echo "\~/.ssh/id_rsa file found, proceeding with the installation... "
else
    echo '\~/.ssh/id_rsa file does not exist'
    echo "Please create the private key for git deployement, then try again"
    exit 1
fi

#check if node is already installed
if type node > /dev/null 2>&1 && which node > /dev/null 2>&1;
then
    node -v
    echo "Node.js is already installed"
else
    echo "Node.js is not installed"
    #Install Build Essentials
    sudo apt-get install -y build-essential openssl libssl-dev pkg-config
    
    ##Install NodeJS
    echo "which Node.js major version you would like to install e.g. 20?"
    read -r NODE_MAJOR
    
    sudo apt-get update && sudo apt-get install -y ca-certificates curl gnupg
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_MAJOR.x nodistro main" | sudo tee /etc/apt/sources.list.d/nodesource.list
    sudo apt-get update && sudo apt-get install nodejs -y
    
    #Check if NodeJs Installed properly
    node -v
    npm -v
fi


#Ask user if it want to install MongoDB
echo "Do you want to install MongoDB? (y/n)"
read -r mongodb
if [ "$mongodb" = "y" ]; then
    echo "Installing MonngoDb"
    sudo apt-get install -y mongodb-org
    
    #create data/bd:
    sudo mkdir /data
    sudo mkdir /data/db
    
    #Start MongoDb
    echo "Starting MongoDb"
    service mongod start
    
    #Verify Installation
    #mongo
    
    #start Mongo when the system starts
    sudo systemctl enable mongod && sudo systemctl start mongod
fi

#Install Redis Cache
echo "Do you wnat to install Redis cache (y/n)?"
read -r redis
if [ "$redis" = "y" ]; then
    echo "Installing Redis"
    sudo npm install redis
    echo "Redis installed"
fi

#check if nginx is already installed
if type nginx > /dev/null 2>&1 && which nginx > /dev/null 2>&1;
then
    echo "Nginx is already installed"
    #Check if nginx is running
    if systemctl is-active --quiet nginx
    then
        echo " and running"
    else
        echo " but not running"
        #Start nginx
        echo -e "Starting Nginx"
        service nginx start
    fi
else
    ##Install nginx
    echo "Installing Nginx"
    sudo apt-get install nginx -y
fi

#Project Setup
echo "What is your project/repository name?"
read -r project
mkdir -p "/var/www/$project"
cd /var/www/"$project" || exit

echo "Do you wnat to clone repository (y/n)?"
read -r repository
if [ "$repository" = "y" ]; then
    echo "Starting git cloning process"
    echo "Make sure you have alredy added public key in your git account for repository deployment"
    
    #secure ssh key and github.com in known_hosts
    chmod 600 ~/.ssh/id_rsa
    ssh-keyscan github.com >> ~/.ssh/known_hosts
    
    #check if git is installed
    if type git > /dev/null 2>&1 && which git > /dev/null 2>&1;
    then
        echo "Git is already installed"
    else
        echo "Git is not installed, now installing..."
        #Install Git
        sudo apt-get install git -y
    fi
    
    #cd to www dir, then clone
    echo "Paste your git url to clone"
    read -r repo_url
    
    cd /var/www || exit
    sudo git clone "$repo_url"
fi

#Configure nginx, create config for your project
cd /etc/nginx/sites-available || exit

echo "-- Configuring Nginx --"
echo "Enter instance private OR local IP address"
read -r private_ip
echo "Enter port where NodeJs server would be running"
read -r node_port
echo "Enter Node.js default dir e.g. v1, v2"
read -r node_dir
echo "Enter server_name e.g. example.com, v1.example.com"
read -r server_name

cat > "$project" << ENDOFFILE
server {
    listen 80;
    server_name $server_name;
    root /var/www/$project/public;
    index index.html index.htm;

  location / {
                # First attempt to serve request as file, then
                # as directory, then fall back to displaying a 404.
                try_files $uri $uri/ =404;
        }

        location /$node_dir {
        proxy_pass http://$private_ip:$node_port;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }

}
ENDOFFILE

#Remove default, its no more required
sudo rm default

#Create a symbolic link from sites-enabled to sites-available
sudo ln -s /etc/nginx/sites-available/"$project" /etc/nginx/sites-enabled/"$project"

#Remove the default from nginx’s sites-enabled diretory:
sudo rm /etc/nginx/sites-enabled/default

#Install SSL
sudo apt remove certbot
sudo snap install --classic certbot
sudo ln -s /snap/bin/certbot /usr/bin/certbot
sudo certbot --nginx  --agree-tos --email ejaz@vintegasolutions.com -n -d "$server_name"
sudo certbot renew -n --dry-run
sudo systemctl reload nginx

#check if npm is already installed
if type npm > /dev/null 2>&1 && which npm > /dev/null 2>&1;
then
    echo "Npm is already installed"
else
    echo "Npm is not installed, now installing..."
    #Install Npm
    sudo apt-get install npm -y
fi

#Installing pm2 and updating project dependencies
echo "Installing pm2"
sudo npm install pm2 -g
cd /var/www/ || exit

sudo chown -R ubuntu "$project"
cd "$project" || exit
sudo npm install

#Sart NodeJs server
pm2 start server.js

#Add pm2 to startup
sudo env PATH=$PATH:/usr/bin /usr/lib/node_modules/pm2/bin/pm2 startup systemd -u ubuntu --hp /home/ubuntu

pm2 save

#Restart nginx
sudo service nginx restart

echo "Setup Ends"
echo "Don't forget to create .env file in your project root dir"
