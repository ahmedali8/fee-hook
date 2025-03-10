# Include .env file and export its environment variables
# (-include to ignore error if it does not exist)
-include .env

DEFAULT_ANVIL_KEY := 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# Foundry Coverage
foundry-report:
	@bash ./shell/foundry-coverage.sh

deploy:
	@forge script script/deploy/OmniHook.s.sol:DeployOmniHook $(NETWORK_ARGS)

NETWORK_ARGS := --rpc-url http://localhost:8545 --private-key $(DEFAULT_ANVIL_KEY) --broadcast

ifeq ($(findstring --network sepolia,$(ARGS)),--network sepolia)
	NETWORK_ARGS := --rpc-url $(SEPOLIA_RPC_URL) --account $(ACCOUNT) --sender $(SENDER) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv
endif

deploy-sepolia:
	@forge script script/deploy/OmniHook.s.sol:DeployOmniHook $(NETWORK_ARGS)