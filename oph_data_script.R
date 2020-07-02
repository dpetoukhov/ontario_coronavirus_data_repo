library(readxl)
library(hash)
library(dplyr)
library(magrittr)

# Temporary files for data extraction
temp_graphs <- tempfile(fileext = ".xlsx")
temp_master <- tempfile(fileext = ".xlsx")

# Core data
graphs_url <- "https://ws1.publichealthontario.ca/appdata/COVID/PROD/graphs.xlsx"
# Metadata
master_url <- "https://ws1.publichealthontario.ca/appdata/COVID/PROD/staticFilesDoNotTouch/master.xlsx"

# Download data
download.file(graphs_url, destfile=temp_graphs, mode='wb')
download.file(master_url, destfile=temp_master, mode='wb')

# Hashmap for converting between the PHU ID and the PHU Name
phu_data <- readxl::read_excel(temp_master, sheet="PHUs")
phu_id <- phu_data$PHU_ID
phu_name <- phu_data$PHU_Name...2
id_to_name_conversion <- hash(phu_id, phu_name) # note, the integer keys (PHU IDs) are strings
name_to_id_conversion <- hash(phu_name, phu_id)

# all_data_hash contains episode date cases, reported date cases, and deaths for each area with a unique PHU ID in Ontario.
# The time-series tibble for each PHU can be accessed via the PHU name; see *keys(all_data_hash)* to see all PHU names.
# Episode date corresponds to the earliest date reported according to the following order: Symptom Onset Date, 
#   Specimen Collection Date, Laboratory Testing Date, Date reported to the province/territory or Date reported to PHAC.
all_data_hash <- hash()
for (i in as.character(phu_id)) {
  all_data_hash[[id_to_name_conversion[[i]]]] <- readxl::read_excel(temp_graphs, sheet=sprintf("Trends%d", as.integer(i))) %>% 
    mutate(Date=as.Date(Date, format="%d-%m-%Y")) %>% mutate(EpisodeDateCases=as.integer(EpisodeDateCases),
                                                             ReportedDateCases=as.integer(ReportedDateCases),
                                                             Deaths=as.integer(Deaths))
}

# Shared date range for all data
date_range <- all_data_hash$Ontario$Date

# *episode_cases* contains the number of episode date cases on a given date in the columns for each PHU
# *reported_cases* contains the number of reported date cases on a given date in the columns for each PHU
# *deaths* contains the number of deaths on a given date in the columns for each PHU
episode_cases <- tibble(date_range) %>% transmute(Date=date_range) %>% group_by(Date)
reported_cases <- tibble(date_range) %>% transmute(Date=date_range) %>% group_by(Date)
deaths <- tibble(date_range) %>% transmute(Date=date_range) %>% group_by(Date)
for (name in phu_name) {
  ep_case_data <- all_data_hash[[name]][c(1,2)]
  rep_case_data <- all_data_hash[[name]][c(1,3)]
  deaths_data <- all_data_hash[[name]][c(1,4)]
  names(ep_case_data) <- names(rep_case_data) <- names(deaths_data) <- c("Date", name)
  episode_cases %<>% left_join(ep_case_data)
  reported_cases %<>% left_join(rep_case_data)
  deaths %<>% left_join(deaths_data)
}


# Conversion for ageID
age_id <- seq(1,11)
ages <- c("0-9", "10-19", "20-29", "30-39", "40-49", "50-59", "60-69", "70-79", "80-89", "90+", "Total")

# *demographic_data_hash* contains the data for each PHU, split by different demographics.
# The rows index different age ranges, and the final row contains the total for each column.
demographic_data_hash <- hash()
demographic_data <- readxl::read_excel(temp_graphs, sheet="ageSex")
for (id in as.character(phu_id)) {
  demographic_data_hash[[id_to_name_conversion[[id]]]] <- demographic_data %>% 
    filter(areaID == as.integer(id)) %>% 
    select(-areaID) %>%
    left_join(tibble(ageID=age_id, ageRange=ages)) %>%
    group_by(ageRange) %>%
    relocate(ageRange, .before = ageID) %>%
    select(-ageID)
}


# Save all relevant data at end of script for direct sharing purposes.
save(all_data_hash, episode_cases, reported_cases, deaths, 
     demographic_data_hash,
     file="corona_data_ontario.RData")
