# Include .env file and export its environment variables
# (-include to ignore error if it does not exist)
-include .env

# Foundry Coverage
foundry-report:
	@bash ./shell/foundry-coverage.sh