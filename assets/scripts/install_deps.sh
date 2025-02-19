#!/bin/bash
if [ $# -ne 1 ]
    then
        echo "Please add cloudformation template name as an argument when running install_deps.sh"
        echo "You can find this in the CloudFormation Console, it will start with mod prefix"
        echo "For example: install_deps.sh mod-47118164636e49dc"
        echo
        exit 1
fi

WORK_DIR=$(pwd)

ROBOT_CERTS_FOLDER=$WORK_DIR/../../robot_ws/src/jetbot_app/config
[ ! -d "$ROBOT_CERTS_FOLDER" ] && mkdir -p $ROBOT_CERTS_FOLDER
SIM_CERTS_FOLDER=$WORK_DIR/../../simulation_ws/src/jetbot_sim_app/config
[ ! -d "$SIM_CERTS_FOLDER" ] && mkdir -p $SIM_CERTS_FOLDER
IOTPOLICY="file://../policies/iotpolicy.json"
IOTPOLICYNAME="JetBotPolicy"

PROJECTNAME=$1
ROBOMAKERFILE="../../roboMakerSettings.json"
AWSCREDSFILE="../teleop/awscreds.js"

#Add cloudformation outputs as variables to use in the rest of this script
for key in $(\
aws cloudformation describe-stacks \
--stack-name $PROJECTNAME \
--query 'Stacks[].Outputs[?OutputKey==`SubmitJobSH`].[OutputValue]' \
--output text
) 
do
    echo $key >> addrobomakerresources.sh
done
source addrobomakerresources.sh
rm addrobomakerresources.sh

#Get IoT Endpoint to update the robomakersettings.json and awscreds.js files
IOTENDPOINT=$(\
aws iot describe-endpoint \
--endpoint-type iot:Data-ATS \
--query 'endpointAddress' \
--output text
)

#Update roboMakerSettings file
echo "Updating roboMakerSettings.json ..."
ROLE_ARN=${ROLE_ARN/\//\\\/}
sed -i "s/<Update S3 Bucketname Here>/$BUCKET_NAME/g" $ROBOMAKERFILE
sed -i "s/<Update IAM Role ARN Here>/$ROLE_ARN/g" $ROBOMAKERFILE
sed -i "s/<Update IoT Endpoint Here>/$IOTENDPOINT/g" $ROBOMAKERFILE
sed -i "s/<Update Public Subnet 1 Here>/$SUBNET1/g" $ROBOMAKERFILE
sed -i "s/<Update Public Subnet 2 Here>/$SUBNET2/g" $ROBOMAKERFILE
sed -i "s/<Update Security Group Here>/$SECURITY_GROUP/g" $ROBOMAKERFILE
mv $ROBOMAKERFILE /home/ubuntu/environment

#Update awscreds.js
echo "Updating awscreds.js ..."
AWSREGION=$(aws configure get region)
sed -i "s/<Update IoT Endpoint Here>/$IOTENDPOINT/g" $AWSCREDSFILE
sed -i "s/<Update Region Here>/$AWSREGION/g" $AWSCREDSFILE
sed -i "s/<Update Access Key ID Here>/$ACCESSKEYID/g" $AWSCREDSFILE
sed -i "s|<Update Secret Access Key Here>|$SECRETACCESSKEY|" $AWSCREDSFILE
zip ../teleop/teleop.zip ../teleop/*

#Create IoT Policy
aws iot create-policy \
--policy-name $IOTPOLICYNAME \
--policy-document $IOTPOLICY

#Create IoT Certificates
#Create two certs for robot_ws and simulation_ws
echo "Creating certificates for robot_ws workspace ..."
ROBOT_CERTARN=$(\
aws iot create-keys-and-certificate --set-as-active \
--certificate-pem-outfile "$ROBOT_CERTS_FOLDER/certificate.pem.crt" \
--private-key-outfile  "$ROBOT_CERTS_FOLDER/private.pem.key" \
--public-key-outfile  "$ROBOT_CERTS_FOLDER/public.pem.key" \
--query "[certificateArn]" \
--output text
)

wget -O $ROBOT_CERTS_FOLDER/root.ca.pem https://www.amazontrust.com/repository/AmazonRootCA1.pem

echo "Creating certificates for simulation_ws workspace ..."
SIM_CERTARN=$(\
aws iot create-keys-and-certificate --set-as-active \
--certificate-pem-outfile "$SIM_CERTS_FOLDER/certificate.pem.crt" \
--private-key-outfile  "$SIM_CERTS_FOLDER/private.pem.key" \
--public-key-outfile  "$SIM_CERTS_FOLDER/public.pem.key" \
--query "[certificateArn]" \
--output text
)

wget -O $SIM_CERTS_FOLDER/root.ca.pem https://www.amazontrust.com/repository/AmazonRootCA1.pem

chmod 755 $SIM_CERTS_FOLDER/* 
chmod 755 $ROBOT_CERTS_FOLDER/*

#attach policy to the certificates
aws iot attach-policy \
--policy-name $IOTPOLICYNAME \
--target $ROBOT_CERTARN

aws iot attach-policy \
--policy-name $IOTPOLICYNAME \
--target $SIM_CERTARN


#Add ROS dependencies
echo "Updating ROS dependencies ..."
cp -a deps/* /etc/ros/rosdep/sources.list.d/ 
echo "yaml file:///$WORK_DIR/jetbot.yaml" > /etc/ros/rosdep/sources.list.d/21-customdepenencies.list
sudo -u ubuntu rosdep update

# The following command logs in to the an AWS Elastic Container Repository (ECR) to
# enable your machine to pull a base docker image

$(aws ecr get-login --no-include-email --registry-ids 593875212637 --region us-east-1)

#Build Docker Container
echo "Building docker image for robot ..."
docker build -t jetbot-ros -f Dockerfile .

#fix ros permissions
rosdep fix-permissions




