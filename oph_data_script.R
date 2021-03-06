library(readxl)
library(hash)
library(dplyr)
library(magrittr)
library(git2r)
library(utils)
library(RSelenium)
library(here)
library(rJava)

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
id_to_name_conversion <- hash::hash(phu_id, phu_name) # note, the integer keys (PHU IDs) are strings
name_to_id_conversion <- hash::hash(phu_name, phu_id)

# all_data_hash contains episode date cases, reported date cases, and deaths for each area with a unique PHU ID in Ontario.
# The time-series tibble for each PHU can be accessed via the PHU name; see *keys(all_data_hash)* to see all PHU names.
# Episode date corresponds to the earliest date reported according to the following order: Symptom Onset Date, 
#   Specimen Collection Date, Laboratory Testing Date, Date reported to the province/territory or Date reported to PHAC.
all_data_hash <- hash::hash()
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
demographic_data_hash <- hash::hash()
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

collection_date <- Sys.Date()
path <- 'D:\\Docs\\Corona Research\\ontario_coronavirus_data_repo\\data'

# Saving all_data_hash
file_name_case_death <- sprintf("%s.rds", collection_date)
file_name_demographics <- sprintf("%s.rds", collection_date)
hash_path_case_death <- paste('D:\\Docs\\Corona Research\\ontario_coronavirus_data_repo\\data\\ontario\\case_death_tibbles\\', 
                              file_name_case_death, sep="")
hash_path_demographics <- paste('D:\\Docs\\Corona Research\\ontario_coronavirus_data_repo\\data\\ontario\\demographics_tibbles\\', 
                                file_name_demographics, sep="")
saveRDS(all_data_hash, hash_path_case_death)
saveRDS(demographic_data_hash, hash_path_demographics)

# Saving all_data_hash by PHU
for (phu in phu_name) {
  phu_path <- file.path('D:\\Docs\\Corona Research\\ontario_coronavirus_data_repo\\data\\ontario\\by_phu\\case_death',
                        phu)
  dir.create(phu_path, showWarnings = FALSE)
  setwd(phu_path)
  write.csv(all_data_hash[[phu]], sprintf("%s.csv", phu))
}

# Saving demographic_data_hash by PHU
for (phu in phu_name) {
  phu_path <- file.path('D:\\Docs\\Corona Research\\ontario_coronavirus_data_repo\\data\\ontario\\by_phu\\demographics',
                        phu)
  dir.create(phu_path, showWarnings = FALSE)
  setwd(phu_path)
  write.csv(demographic_data_hash[[phu]], sprintf("%s.csv", phu))
}

# Creating and saving PHU adjacency list
phu_adjacency <- hash::hash()
phu_adjacency[["Algoma Public Health"]] <- c("Thunder Bay District Health Unit", "Porcupine Health Unit", "Public Health Sudbury & Districts")
phu_adjacency[["Brant County Health Unit"]] <- c("Region of Waterloo Public Health and Emergency Services", 
                                                 "City of Hamilton Public Health Services",
                                                 "Haldimand-Norfolk Health Unit", "Southwestern Public Health")
phu_adjacency[["Chatham-Kent Public Health"]] <- c("Windsor-Essex County Health Unit", "Southwestern Public Health", "Middlesex-London Health Unit",
                                                   "Lambton Public Health")
phu_adjacency[["City of Hamilton Public Health Services"]] <- c("Niagara Region Public Health", "Haldimand-Norfolk Health Unit", 
                                                                "Brant County Health Unit", "Region of Waterloo Public Health and Emergency Services",
                                                                "Wellington-Dufferin-Guelph Public Health", "Halton Region Public Health")
phu_adjacency[["Durham Region Health Department"]] <- c("Toronto Public Health", "York Region Public Health", "Simcoe Muskoka District Health Unit",
                                                        "Haliburton, Kawartha, Pine Ridge District Health Unit", "Peterborough Public Health")
phu_adjacency[["Eastern Ontario Health Unit"  ]] <- c("Ottawa Public Health", "Leeds, Grenville & Lanark District Health Unit")
phu_adjacency[["Grey Bruce Health Unit"]] <- c("Simcoe Muskoka District Health Unit", "Wellington-Dufferin-Guelph Public Health", 
                                               "Huron Perth Health Unit")
phu_adjacency[["Haldimand-Norfolk Health Unit" ]] <- c("Niagara Region Public Health", "City of Hamilton Public Health Services", 
                                                       "Brant County Health Unit", "Southwestern Public Health")
phu_adjacency[["Haliburton, Kawartha, Pine Ridge District Health Unit"]] <- c("Simcoe Muskoka District Health Unit", "York Region Public Health",
                                                                              "Durham Region Health Department", "Peterborough Public Health",
                                                                              "Hastings Prince Edward Public Health", 
                                                                              "Renfrew County and District Health Unit",
                                                                              "North Bay Parry Sound District Health Unit")
phu_adjacency[["Halton Region Public Health" ]] <- c("Peel Public Health", "Wellington-Dufferin-Guelph Public Health",
                                                     "City of Hamilton Public Health Services")
phu_adjacency[["Hastings Prince Edward Public Health" ]] <- c("Renfrew County and District Health Unit", 
                                                              "Kingston, Frontenac and Lennox & Addington Public Health",
                                                              "Haliburton, Kawartha, Pine Ridge District Health Unit",
                                                              "Peterborough Public Health")
phu_adjacency[["Huron Perth Health Unit"]] <- c("Grey Bruce Health Unit", "Middlesex-London Health Unit", "Southwestern Public Health",
                                                "Lambton Public Health", "Wellington-Dufferin-Guelph Public Health", 
                                                "Region of Waterloo Public Health and Emergency Services")
phu_adjacency[["Kingston, Frontenac and Lennox & Addington Public Health"]] <- c("Hastings Prince Edward Public Health",
                                                                                 "Renfrew County and District Health Unit",
                                                                                 "Leeds, Grenville & Lanark District Health Unit")
phu_adjacency[["Lambton Public Health"]] <- c("Huron Perth Health Unit", "Middlesex-London Health Unit", "Chatham-Kent Public Health",
                                              "Southwestern Public Health")
phu_adjacency[["Leeds, Grenville & Lanark District Health Unit"]] <- c("Eastern Ontario Health Unit", "Ottawa Public Health",
                                                                       "Kingston, Frontenac and Lennox & Addington Public Health",
                                                                       "Renfrew County and District Health Unit")
phu_adjacency[["Middlesex-London Health Unit"]] <- c("Huron Perth Health Unit", "Southwestern Public Health", "Chatham-Kent Public Health",
                                                     "Lambton Public Health")
phu_adjacency[["Niagara Region Public Health"]] <- c("City of Hamilton Public Health Services", "Haldimand-Norfolk Health Unit")
phu_adjacency[["North Bay Parry Sound District Health Unit"]] <- c("Public Health Sudbury & Districts", "Timiskaming Health Unit",
                                                                   "Renfrew County and District Health Unit", "Simcoe Muskoka District Health Unit",
                                                                   "Haliburton, Kawartha, Pine Ridge District Health Unit")
phu_adjacency[["Northwestern Health Unit"]] <- c("Thunder Bay District Health Unit")
phu_adjacency[["Ottawa Public Health"]] <- c("Eastern Ontario Health Unit", "Leeds, Grenville & Lanark District Health Unit",
                                             "Renfrew County and District Health Unit")
phu_adjacency[["Peel Public Health"]] <- c("Toronto Public Health" , "York Region Public Health", "Simcoe Muskoka District Health Unit",
                                           "Wellington-Dufferin-Guelph Public Health", "Halton Region Public Health")
phu_adjacency[["Peterborough Public Health"]] <- c("Haliburton, Kawartha, Pine Ridge District Health Unit", "Durham Region Health Department",
                                                   "Hastings Prince Edward Public Health")
phu_adjacency[["Porcupine Health Unit"]] <- c("Thunder Bay District Health Unit", "Algoma Public Health", "Public Health Sudbury & Districts",
                                              "Timiskaming Health Unit")
phu_adjacency[["Public Health Sudbury & Districts"]] <- c("Algoma Public Health", "Porcupine Health Unit", "Timiskaming Health Unit",
                                                          "North Bay Parry Sound District Health Unit")
phu_adjacency[["Region of Waterloo Public Health and Emergency Services"]] <- c("Wellington-Dufferin-Guelph Public Health",
                                                                                "City of Hamilton Public Health Services", "Brant County Health Unit",
                                                                                "Huron Perth Health Unit", "Southwestern Public Health")
phu_adjacency[["Renfrew County and District Health Unit"]] <- c("North Bay Parry Sound District Health Unit",
                                                                "Haliburton, Kawartha, Pine Ridge District Health Unit",
                                                                "Hastings Prince Edward Public Health",
                                                                "Kingston, Frontenac and Lennox & Addington Public Health",
                                                                "Leeds, Grenville & Lanark District Health Unit", "Ottawa Public Health")
phu_adjacency[["Simcoe Muskoka District Health Unit"]] <- c("North Bay Parry Sound District Health Unit", 
                                                            "Haliburton, Kawartha, Pine Ridge District Health Unit",
                                                            "Durham Region Health Department", "York Region Public Health", "Peel Public Health",
                                                            "Wellington-Dufferin-Guelph Public Health", "Grey Bruce Health Unit")
phu_adjacency[["Southwestern Public Health"]] <- c("Chatham-Kent Public Health", "Lambton Public Health", "Middlesex-London Health Unit",
                                                   "Huron Perth Health Unit", "Region of Waterloo Public Health and Emergency Services",
                                                   "Brant County Health Unit", "Haldimand-Norfolk Health Unit")
phu_adjacency[["Thunder Bay District Health Unit"]] <- c("Algoma Public Health", "Northwestern Health Unit", "Porcupine Health Unit")
phu_adjacency[["Timiskaming Health Unit"]] <- c("Porcupine Health Unit", "Public Health Sudbury & Districts", 
                                                "North Bay Parry Sound District Health Unit")
phu_adjacency[["Toronto Public Health"]] <- c("Peel Public Health", "York Region Public Health", "Durham Region Health Department")
phu_adjacency[["Wellington-Dufferin-Guelph Public Health"]] <- c("Huron Perth Health Unit", "Grey Bruce Health Unit", 
                                                                 "Simcoe Muskoka District Health Unit", "Peel Public Health",
                                                                 "Halton Region Public Health", "City of Hamilton Public Health Services",
                                                                 "Region of Waterloo Public Health and Emergency Services")
phu_adjacency[["Windsor-Essex County Health Unit"]] <- c("Chatham-Kent Public Health")
phu_adjacency[["York Region Public Health"]] <- c("Toronto Public Health", "Peel Public Health", "Simcoe Muskoka District Health Unit",
                                                  "Haliburton, Kawartha, Pine Ridge District Health Unit", "Durham Region Health Department")

setwd('D:\\Docs\\Corona Research\\ontario_coronavirus_data_repo\\data\\ontario\\phu_adjacency')
# Saving hash as R object
save(phu_adjacency, file="adjacency_hash.Robj")
# Saving hash as JSON ------- THIS DOES NOT WORK YET
# adjacency_to_JSON <- toJSON(phu_adjacency)
# write(adjacency_to_JSON, "adjacency.json")


# Pulling global data set from European Centre for Disease Prevention and Control
global_data <- read.csv("https://opendata.ecdc.europa.eu/covid19/casedistribution/csv", 
                        na.strings = "", fileEncoding = "UTF-8-BOM")
global_data$dateRep <- as.Date(global_data$dateRep, format="%d/%m/%Y")
dir.create('D:\\Docs\\Corona Research\\ontario_coronavirus_data_repo\\data\\case_distribution_world\\all_countries',
           showWarnings = FALSE)
setwd('D:\\Docs\\Corona Research\\ontario_coronavirus_data_repo\\data\\case_distribution_world\\all_countries')
write.csv(global_data, "all_countries.csv")
country_names <- unique(global_data$countriesAndTerritories)
for (country in country_names) {
  country_path <- file.path('D:\\Docs\\Corona Research\\ontario_coronavirus_data_repo\\data\\case_distribution_world',
                            country)
  dir.create(country_path, showWarnings = FALSE)
  setwd(country_path)
  write.csv(global_data[global_data$countriesAndTerritories == country,], sprintf("%s.csv", country))
}



# Pulling test data
#
testing_url <- "https://covid-19.ontario.ca/data"
file_name <- "testing_data_ontario.csv"
download_location <- file.path(Sys.getenv("USERPROFILE"), "Downloads")
driver <- rsDriver(
  broswer = "chrome",
  chromever = "84.0.4147.89"
)
#driver <- remoteDriver()
#driver$open
#driver$navigate(testing_url)
server <- driver$server
browser <- driver$client
browser$navigate(url)
buttons <- list()
while (length(buttons) == 0) {
  buttons <- browser$findElements(
    "apexcharts34e94f > div.apexcharts-toolbar > div.apexcharts-menu.apexcharts-menu-open > div.apexcharts-menu-item.exportCSV",
    using = "css selector"
  )
}
buttons[[1]]$clickElement()
browser$close()
server$stop()



# # Save all relevant data at end of script for direct sharing purposes.
# save(all_data_hash, episode_cases, reported_cases, deaths, 
#      demographic_data_hash,
#      file="corona_data_ontario.RData")

# Git helper functions:
gitstatus <- function(dir = getwd()){
  cmd_list <- list(
    cmd1 = tolower(substr(dir,1,2)),
    cmd2 = paste("cd",dir),
    cmd3 = "git status"
  )
  cmd <- paste(unlist(cmd_list),collapse = " & ")
  shell(cmd)
}

gitadd <- function(dir = getwd()){
  cmd_list <- list(
    cmd1 = tolower(substr(dir,1,2)),
    cmd2 = paste("cd",dir),
    cmd3 = "git add --all"
  )
  cmd <- paste(unlist(cmd_list),collapse = " & ")
  shell(cmd)
}

gitpush <- function(dir = getwd()){
  cmd_list <- list(
    cmd1 = tolower(substr(dir,1,2)),
    cmd2 = paste("cd",dir),
    cmd3 = "git push"
  )
  cmd <- paste(unlist(cmd_list),collapse = " & ")
  shell(cmd)
}

gitcommit <- function(msg = "commit from Rstudio", dir = getwd()){
  cmd = sprintf("git commit -m\"%s\"",msg)
  system(cmd)
}

# Pushing to git
git_dir <- 'D:\\Docs\\Corona Research\\ontario_coronavirus_data_repo'
setwd(git_dir)
git2r::config(user.name = "dpetoukhov", user.email = "dpetoukhov@gmail.com")
gitstatus()
gitadd()
gitcommit()
gitpush()

# incidence = new cases, prevalance = aggregate cases

# Try PCA analysis on new data; many of it is correlated.
# Use standard time series GLM

# number of tests: https://covid-19.ontario.ca/data
# tscount: for count time series
# if using cases as covariates, need to forecast those first
# random effects model
# use regular GLM
# tscount: for exponential model (1), use log link function (g function)
# add Fourier term to denote a 7 day cycle (deaths are always low on weekends) (use a harmonic function); or put in dummy variable for each day of week.

