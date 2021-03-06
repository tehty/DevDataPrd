library(shiny)

# Plot
library(ggplot2)
library(rCharts)
library(ggvis)

# Data processing
library(data.table)
library(reshape2)
library(dplyr)

# Markdown
library(markdown)

# To plot ggplot maps
library(mapproj)
library(maps)

# All Functions
# ----------------------------------------------------------------------------------
# Aggregate by state function

aggregate_by_state <- function(dt, year_min, year_max, evtypes) {
  replace_na <- function(x) ifelse(is.na(x), 0, x)
  round_2 <- function(x) round(x, 2)
  
  states <- data.table(STATE=sort(unique(dt$STATE)))
  
  aggregated <- dt %>% filter(YEAR >= year_min, YEAR <= year_max, EVTYPE %in% evtypes) %>%
    group_by(STATE) %>%
    summarise_each(funs(sum), COUNT:CROPDMG)
  
  # We want all states to be present 
  left_join(states,  aggregated, by = "STATE") %>%
    mutate_each(funs(replace_na), FATALITIES:CROPDMG) %>%
    mutate_each(funs(round_2), PROPDMG, CROPDMG)    
}

# Aggregate by year function
# 
aggregate_by_year <- function(dt, year_min, year_max, evtypes) {
  round_2 <- function(x) round(x, 2)
  
  # Filter
  dt %>% filter(YEAR >= year_min, YEAR <= year_max, EVTYPE %in% evtypes) %>%
    # Group and aggregate
    group_by(YEAR) %>% summarise_each(funs(sum), COUNT:CROPDMG) %>%
    # Round
    mutate_each(funs(round_2), PROPDMG, CROPDMG) %>%
    rename(
      Year = YEAR, Count = COUNT,
      Fatalities = FATALITIES, Injuries = INJURIES,
      Property = PROPDMG, Crops = CROPDMG
    )
}

# Affected column based on category

compute_affected <- function(dt, category) {
  dt %>% mutate(Affected = {
    if(category == 'both') {
      INJURIES + FATALITIES
    } else if(category == 'fatalities') {
      FATALITIES
    } else {
      INJURIES
    }
  })
}

# Damages column based on category

compute_damages <- function(dt, category) {
  dt %>% mutate(Damages = {
    if(category == 'both') {
      PROPDMG + CROPDMG
    } else if(category == 'crops') {
      CROPDMG
    } else {
      PROPDMG
    }
  })
}

# Prepare map of economic/population impact

plot_impact_by_state <- function (dt, states_map, year_min, year_max, fill, title, low = "#54f07e", high = "#f43c1c") {
  title <- sprintf(title, year_min, year_max)
  p <- ggplot(dt, aes(map_id = STATE))
  p <- p + geom_map(aes_string(fill = fill), map = states_map, colour='black')
  p <- p + expand_limits(x = states_map$long, y = states_map$lat)
  p <- p + coord_map() + theme_bw()
  p <- p + labs(x = "Long", y = "Lat", title = title)
  p + scale_fill_gradient(low = low, high = high)
}

# Prepare plots of impact by year
 
plot_impact_by_year <- function(dt, dom, yAxisLabel, desc = FALSE) {
  impactPlot <- nPlot(
    value ~ Year, group = "variable",
    data = melt(dt, id="Year") %>% arrange(Year, if (desc) { desc(variable) } else { variable }),
    type = "stackedAreaChart", dom = dom, width = 650
  )
  impactPlot$chart(margin = list(left = 100))
  impactPlot$yAxis(axisLabel = yAxisLabel, width = 80)
  impactPlot$xAxis(axisLabel = "Year", width = 70)
  
  impactPlot
}

# Prepare plot of number of events by year

plot_events_by_year <- function(dt, dom = "eventsByYear", yAxisLabel = "Count") {
  eventsByYear <- nPlot(
    Count ~ Year,
    data = dt,
    type = "lineChart", dom = dom, width = 650
  )
  
  eventsByYear$chart(margin = list(left = 100))
  eventsByYear$yAxis( axisLabel = yAxisLabel, width = 80)
  eventsByYear$xAxis( axisLabel = "Year", width = 70)
  eventsByYear
}

# Prepare dataset for download

prepare_downolads <- function(dt) {
  dt %>% rename(
    State = STATE, Count = COUNT,
    Injuries = INJURIES, Fatalities = FATALITIES,
    Property.damage = PROPDMG, Crops.damage = CROPDMG
  ) %>% mutate(State=state.abb[match(State, tolower(state.name))])
}

#--------- end of functions ---------------

# Load text data from subfolder
states_map <- map_data("state")
dt <- fread('data/events.csv') %>% mutate(EVTYPE = tolower(EVTYPE))
evtypes <- sort(unique(dt$EVTYPE))

# Shiny server 
shinyServer(function(input, output, session) {
    
    # Define and initialize reactive values
    values <- reactiveValues()
    values$evtypes <- evtypes
    
    # Create event type checkbox
    output$evtypeControls <- renderUI({
        checkboxGroupInput('evtypes', 'Event types', evtypes, selected=values$evtypes)
    })
    
    # Add clear and select all buttons
    observe({
        if(input$clear_all == 0) return()
        values$evtypes <- c()
    })
    
    observe({
        if(input$select_all == 0) return()
        values$evtypes <- evtypes
    })

    # Prepare dataset for maps
    dt.agg <- reactive({
        aggregate_by_state(dt, input$range[1], input$range[2], input$evtypes)
    })
    
    # Prepare dataset for time series
    dt.agg.year <- reactive({
        aggregate_by_year(dt, input$range[1], input$range[2], input$evtypes)
    })
    
    # Prepare dataset for downloads
    dataTable <- reactive({
        prepare_downolads(dt.agg())
    })
    
    # Population impact by state
    output$populationImpactByState <- renderPlot({
        print(plot_impact_by_state (
            dt = compute_affected(dt.agg(), input$populationCategory),
            states_map = states_map, 
            year_min = input$range[1],
            year_max = input$range[2],
            title = "Population impact %d - %d (number of affected)",
            fill = "Affected"
        ))
    })
    
    # Economic impact by state
    output$economicImpactByState <- renderPlot({
        print(plot_impact_by_state(
            dt = compute_damages(dt.agg(), input$economicCategory),
            states_map = states_map, 
            year_min = input$range[1],
            year_max = input$range[2],
            title = "Economic impact %d - %d (Million USD)",
            fill = "Damages"
        ))
    })
    
    # Events by year
    output$eventsByYear <- renderChart({
       plot_events_by_year(dt.agg.year())
    })
    
    # Population impact by year
    output$populationImpact <- renderChart({
        plot_impact_by_year(
            dt = dt.agg.year() %>% select(Year, Injuries, Fatalities),
            dom = "populationImpact",
            yAxisLabel = "Affected",
            desc = TRUE
        )
    })
    
    # Economic impact by state
    output$economicImpact <- renderChart({
        plot_impact_by_year(
            dt = dt.agg.year() %>% select(Year, Crops, Property),
            dom = "economicImpact",
            yAxisLabel = "Total damage (Million USD)"
        )
    })
    
    # Render data table and create downloader
    output$table <- renderDataTable(
        {dataTable()}, options = list(bFilter = FALSE, iDisplayLength = 50))
    
    output$downloadData <- downloadHandler(
        filename = 'data.csv',
        content = function(file) {
            write.csv(dataTable(), file, row.names=FALSE)
        }
    )
})


