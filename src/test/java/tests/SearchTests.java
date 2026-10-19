package tests;

import org.junit.jupiter.api.Test;
import pages.SearchPage;

import static com.codeborne.selenide.Selenide.open;

public class SearchTests extends TestBase {
    @Test
    void successfulSearchTest() {
        SearchPage searchPage = open("/search", SearchPage.class);
        searchPage.searchFor("qa.guru")
                .shouldHaveResultsContaining("QA.GURU");
    }

    @Test
    void openRepositoryFromSearchResultsTest() {
        SearchPage searchPage = open("/search", SearchPage.class);
        searchPage.searchFor("selenide/selenide")
                .openResult("selenide/selenide")
                .shouldHaveUrl("https://github.com/selenide/selenide")
                .shouldHaveName("selenide");
    }

    @Test
    void noResultsForHugeStarsCountTest() {
        SearchPage searchPage = open("/search", SearchPage.class);
        searchPage.searchFor("stars:>999999999")
                .shouldHaveNoResults();
    }
}
