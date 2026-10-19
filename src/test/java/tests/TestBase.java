package tests;

import com.codeborne.selenide.Configuration;
import com.codeborne.selenide.logevents.SelenideLogger;
import io.qameta.allure.jupiter.AllureJupiter;
import io.qameta.allure.selenide.AllureSelenide;
import io.qameta.allure.selenide.LogType;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.extension.ExtendWith;

import java.util.logging.Level;

import static com.codeborne.selenide.Selenide.closeWebDriver;

@ExtendWith(AllureJupiter.class)
public class TestBase {
    @BeforeAll
    static void configureBrowser() {
        Configuration.baseUrl = configurationValue("selenide.baseUrl", "UI_BASE_URL", "https://github.com");
        Configuration.browser = configurationValue("selenide.browser", "UI_BROWSER", "chrome");
        Configuration.browserSize = configurationValue("selenide.browserSize", "UI_BROWSER_SIZE", "1920x1080");
        Configuration.headless = Boolean.parseBoolean(configurationValue("selenide.headless", "UI_HEADLESS", "false"));

        AllureSelenide allure = new AllureSelenide()
                .includeSelenideSteps(false)
                .screenshots(true)
                .savePageSource(true);
        if ("chrome".equals(Configuration.browser)) {
            allure.enableLogs(LogType.BROWSER, Level.ALL);
        }
        SelenideLogger.addListener("allure", allure);
    }

    @AfterEach
    void closeBrowser() {
        closeWebDriver();
    }

    private static String configurationValue(String propertyName, String environmentVariableName, String defaultValue) {
        String value = System.getProperty(propertyName);
        if (value == null) {
            value = System.getenv(environmentVariableName);
        }
        return value != null ? value : defaultValue;
    }
}
