# Script utilizado para gerar configurações de integração de concentradores no SGP
> Execução: Para executar o script em Linux:
```
apt-get install wget -y
```
```
wget -qO - https://download.sublimetext.com/sublimehq-pub.gpg | sudo apt-key add -
```
```
echo "deb https://download.sublimetext.com/ apt/stable/" | sudo tee /etc/apt/sources.list.d/sublime-text.list
```
```
sudo apt-get update
```
```
sudo apt-get install sublime-text -y
```
```
wget -O-  https://raw.githubusercontent.com/Ednardo-Pedrosa/integracao-nas/main/integranas.sh > /tmp/.i.sh && sh /tmp/.i.sh
```
