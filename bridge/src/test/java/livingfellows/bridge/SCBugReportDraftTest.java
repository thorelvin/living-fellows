// SPDX-License-Identifier: MIT
package livingfellows.bridge;

import java.util.ArrayList;
import java.util.List;

public final class SCBugReportDraftTest {
    private static void require(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }

    public static void main(String[] args) throws Exception {
        require(Class.forName("zombie.network.DesktopBrowser").getMethod("openURL", String.class)
                .getReturnType() == boolean.class, "game's desktop browser signature changed");
        require(!SCBridge.openBugReportDraft(null), "missing report must leave the browser closed");
        String draft = "https://github.com/thorelvin/living-fellows/issues/new?template=bug_report.yml"
                + "&title=Bug&problem=Radio%20silent%20%26%20TV%20muted&reproduce=Press%20play%0AWait"
                + "&mod-version=0.27.52&game-version=42.22.2&logs=Power%20Night";
        List<String> opened = new ArrayList<>();
        require(SCBugReportDraft.open(draft, opened::add) && opened.equals(List.of(draft)),
                "expected one unchanged, reviewed URL");
        for (String invalid : List.of(draft.replace("https:", "http:"), draft.replace("github.com", "example.org"),
                draft.replace("issues/new", "settings"), draft.replace("bug_report.yml", "feature_request.yml"),
                draft.replace("&logs=", "&labels="), draft.replace("title=Bug", "title="), draft + "&extra=1",
                draft + "#more", draft + "%", draft + " ", draft + "a".repeat(4000))) {
            require(!SCBugReportDraft.open(invalid, opened::add), "invalid draft accepted");
        }
        require(opened.size() == 1, "invalid drafts reached the browser");
        require(!SCBugReportDraft.open(draft, url -> false), "desktop refusal must reach the form");
        require(!SCBugReportDraft.open(draft, url -> { throw new SecurityException(); }),
                "unavailable desktop must allow clipboard fallback");
        System.out.println("BUG_REPORT_BROWSER_PASS");
    }
}
