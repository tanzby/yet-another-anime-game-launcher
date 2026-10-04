import { FormControl, FormLabel, Box, Checkbox } from "@hope-ui/solid";
import { createEffect, createSignal } from "solid-js";
import { Locale } from "@locale";
import { assertValueDefined, getKeyOrDefault, setKey } from "@utils";
import { Config, NOOP } from "@config/config-def";

declare module "@config/config-def" {
  interface Config {
    gameMode: boolean;
  }
}

const CONFIG_KEY = "config_game_mode";

export default async function ({
  locale,
  config,
}: {
  config: Partial<Config>;
  locale: Locale;
}) {
  config.gameMode = (await getKeyOrDefault(CONFIG_KEY, "true")) != "false";

  const [value, setValue] = createSignal(config.gameMode);

  async function onSave(apply: boolean) {
    assertValueDefined(config.gameMode);
    if (!apply) {
      setValue(config.gameMode);
      return NOOP;
    }
    if (config.gameMode == value()) return NOOP;
    config.gameMode = value();
    await setKey(CONFIG_KEY, config.gameMode ? "true" : "false");
    return NOOP;
  }

  createEffect(() => {
    value();
    onSave(true);
  });

  return [
    function UI() {
      return (
        <FormControl id="gameMode">
          <FormLabel>{locale.get("SETTING_GAME_MODE")}</FormLabel>
          <Box>
            <Checkbox
              checked={value()}
              onChange={() => setValue(x => !x)}
              size="md"
            >
              {locale.get("SETTING_ENABLED")}
            </Checkbox>
          </Box>
        </FormControl>
      );
    },
  ] as const;
}
