package pages;

import com.codeborne.selenide.SelenideElement;

import static com.codeborne.selenide.Condition.exactText;
import static com.codeborne.selenide.Selenide.$;
import static com.codeborne.selenide.Selenide.webdriver;
import static com.codeborne.selenide.WebDriverConditions.url;
import static io.qameta.allure.Allure.step;

public class RepositoryPage {
    private final SelenideElement repoNameLink = $("#repo-title-component a[data-testid='repo-name-link']");

    public RepositoryPage shouldHaveUrl(String expectedUrl) {
        step("Verify repository URL: " + expectedUrl, () -> {
            webdriver().shouldHave(url(expectedUrl));
        });
        return this;
    }

    public RepositoryPage shouldHaveName(String expectedName) {
        step("Verify repository name: " + expectedName, () -> {
            repoNameLink.shouldHave(exactText(expectedName));
        });
        return this;
    }
}
