APP_NAME := Inkognito

BUILD_DIR := build
APP       := $(BUILD_DIR)/$(APP_NAME).app
DMG       := $(BUILD_DIR)/$(APP_NAME).dmg

.PHONY: dmg clean

dmg:
	@test -d "$(APP)" || (echo "error: $(APP) not found — copy your signed .app into build/ first" && exit 1)
	scripts/make-dmg.sh "$(APP)" "$(DMG)"

clean:
	rm -rf $(BUILD_DIR)
