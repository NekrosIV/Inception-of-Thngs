all:
	sudo bash ./scripts/setup.sh
	sudo bash ./scripts/init.sh

clean:
	k3d cluster delete my-cluster

re: clean all