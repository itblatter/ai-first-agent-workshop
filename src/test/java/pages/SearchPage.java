package pages;

import com.codeborne.selenide.SelenideElement;

import java.time.Duration;

import static com.codeborne.selenide.Condition.exist;
import static com.codeborne.selenide.Condition.text;
import static com.codeborne.selenide.Selenide.$;
import static io.qameta.allure.Allure.step;

public class SearchPage {
    private final SelenideElement searchInput = $("[aria-label='Search GitHub']");
    private final SelenideElement resultsList = $("[data-testid='results-list']");
    private final SelenideElement main = $("main");

    public SearchPage searchFor(String query) {
        step("Search repositories for: " + query, () -> {
            searchInput.setValue(query).pressEnter();
        });

        return this;
    }

    public RepositoryPage openResult(String repositoryPath) {
        return step("Open repository from search results: " + repositoryPath, () -> {
            resultsList.$("a[href='/" + repositoryPath + "']").click();
            return new RepositoryPage();
        });
    }

    public SearchPage shouldHaveResultsContaining(String expectedText) {
        step("Verify search results contain: " + expectedText, () -> {
            resultsList.shouldHave(text(expectedText));
        });

        return this;
    }

    public SearchPage shouldHaveNoResults() {
        step("Verify there are no matching repositories", () -> {
            main.shouldHave(text("Your search did not match any repositories"), Duration.ofSeconds(30));
            main.shouldHave(text("0 results"));
            resultsList.shouldNot(exist);
        });

        return this;
    }
}
