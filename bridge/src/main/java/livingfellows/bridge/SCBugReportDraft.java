// SPDX-License-Identifier: MIT
package livingfellows.bridge;

import java.util.function.Predicate;
import java.util.regex.Pattern;

final class SCBugReportDraft {
    private static final String FORM =
            "https://github.com/thorelvin/living-fellows/issues/new?template=bug_report.yml&";
    private static final String[] FIELDS =
            {"title", "problem", "reproduce", "mod-version", "game-version", "logs"};
    private static final Pattern ENCODED_TEXT = Pattern.compile("(?:[A-Za-z0-9._~-]|%[A-Fa-f0-9]{2})++");

    private SCBugReportDraft() {}

    // The game may run AWT-headless. Use its platform browser, with authority
    // limited to this form and the six encoded text fields shown in the preview.
    static boolean open(String url, Predicate<String> browser) {
        if (url == null || url.length() > 4000 || !url.startsWith(FORM)) return false;
        String[] fields = url.substring(FORM.length()).split("&", -1);
        if (fields.length != FIELDS.length) return false;
        for (int i = 0; i < fields.length; i++) {
            String prefix = FIELDS[i] + "=";
            if (!fields[i].startsWith(prefix)
                    || !ENCODED_TEXT.matcher(fields[i].substring(prefix.length())).matches()) return false;
        }
        try {
            return browser.test(url);
        } catch (RuntimeException | LinkageError unavailable) {
            return false;
        }
    }
}
