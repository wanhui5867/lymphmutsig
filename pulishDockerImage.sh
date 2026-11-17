#1. open Docker desktop 
#2. create the Dockerfile in the parent directory of shiny app

#3. create the app image using below commands
# cd the path where Dockfile is & Make sure the genome/ directory is under the same path

#docker buildx rm lymphmutsig
#docker buildx create --name lymphmutsig
#docker buildx use lymphmutsig
#docker buildx inspect --bootstrap
#docker buildx build --tag 20250220 -o type=image --platform=linux/amd64 .
#docker buildx build --push --tag huiwan5867/lymphmutsig:20250220 --platform=linux/amd64 .

#docker run --rm  --platform linux/amd64  -p 3838:3838 huiwan5867/lymphmutsig:20250220


docker build --platform linux/amd64 -t huiwan5867/lymphmutsig:20261116  -f Dockerfile .
docker image ls
docker push huiwan5867/lymphmutsig:20261116
docker run --rm -p 3838:3838 huiwan5867/lymphmutsig:20261116
docker run -it --rm -p 3838:3838 huiwan5867/lymphmutsig:20261116 /bin/bash #进入容器
cd /srv/shiny-server/app
ls
docker exec -it 20261116 /bin/bash
