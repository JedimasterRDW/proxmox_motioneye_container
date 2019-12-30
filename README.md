# proxmox motioneye container
This link/script will Install MotionEye in a proxmox container and config the defaults.

To create the MotionEye container in Proxmox you have to open a SSH shell or console and copy this link in it and hit "Enter"

```
bash -c "$(wget -qLO - https://raw.githubusercontent.com/JedimasterRDW/proxmox_motioneye_container/master/create_container.sh)"
```
After the installation is done it wil give you the information to connect to the MotionEye Web interface.

## Reference
I made this script with the help of whiskerz007 and a lot of thanks for that!
It was nice working together with you.
To see all his great work visit https://github.com/whiskerz007

## How to Add a MotionEye camera to Home Assistant
You have to put the following code to you configuration.yaml file and add your MotionEye/Camara information
```
camera: #verify that you don't have it in your configuration.yaml already, if you do so, skip this line.
  - platform: mjpeg
    name: MotionEye Test Cam # your camara name
    still_image_url: # copy from your motionEye page - Video streaming - Snapshot URL
    mjpeg_url: # MotionEye IP address with the port that you have configured (e.g: http://192.168.1.123:8888) 
    username: !secret motion_user # dont forget to put the name and password in your secret file
    password: !secret motion_pass
```
when your done with the configuration.yaml file save it and restart.
After reboot you can add the camera to the Lovelace UI
