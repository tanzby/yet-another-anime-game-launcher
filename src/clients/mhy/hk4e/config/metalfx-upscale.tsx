import { FormControl, FormLabel, Box, Checkbox } from "@hope-ui/solid";
import { createEffect, createSignal } from "solid-js";
import { Locale } from "@locale";
import { assertValueDefined, getKeyOrDefault, setKey } from "@utils";
import { Config, NOOP } from "@config/config-def";

declare module "@config/config-def" {
  interface Config {
    metalFxUpscale: boolean;
  }
}

const CONFIG_KEY = "config_metalfx_upscale";

export default async function ({
  locale,
  config,
}: {
  config: Partial<Config>;
  locale: Locale;
}) {
  config.metalFxUpscale =
    (await getKeyOrDefault(CONFIG_KEY, "false")) == "true";

  const [value, setValue] = createSignal(config.metalFxUpscale);

  async function onSave(apply: boolean) {
    assertValueDefined(config.metalFxUpscale);
    if (!apply) {
      setValue(config.metalFxUpscale);
      return NOOP;
    }
    if (config.metalFxUpscale == value()) return NOOP;
    config.metalFxUpscale = value();
    await setKey(CONFIG_KEY, config.metalFxUpscale ? "true" : "false");
    return NOOP;
  }

  createEffect(() => {
    value();
    onSave(true);
  });

  return [
    function UI() {
      return (
        <FormControl id="metalFxUpscale">
          <FormLabel>{locale.get("SETTING_METALFX_UPSCALE")}</FormLabel>
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
