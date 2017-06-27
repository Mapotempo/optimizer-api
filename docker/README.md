Optimizer deployment using docker-compose
=========================================

    cp ../config/environments/production.rb ./
    # Edit production.rb file to match your needs
    docker-compose build
    docker-compose -p optimizer up -d
