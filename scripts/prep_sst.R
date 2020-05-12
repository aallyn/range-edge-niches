# this script will get gridded netcdf SST data from NOAA's ERDDAP server, resample the lower-resolution datasets, crop them to the extent of the study regions, and write SST out as dataframes

library(rerddap)
library(raster)
library(oceanmap)
library(sf)
library(tidyverse)
library(here)
library(tabularaster)
library(lubridate)
library(purrr)

map <- purrr::map
here <- here::here

source(here("functions","sfc_as_cols.R"))

#####################
### get ERDDAP data
#####################

# select bounding boxes for all regions 
neus_latrange <- c(35, 45)
neus_lonrange <- c(-78, -66) 
wc_latrange <- c(30, 50)
wc_lonrange <- c(-126, -117)
ebs_latrange <- c(54, 66)
ebs_lonrange <- c(-179.5, -154)

# program call for each dataset; get from the ERDDAP pages and update end years if more data is added
# https://coastwatch.pfeg.noaa.gov/erddap/griddap/erdHadISST.html
# https://coastwatch.pfeg.noaa.gov/erddap/griddap/ncdcOisst2Agg_LonPM180.html

hadisst <- "erdHadISST"
hadisst_fields <- "sst"

neus_hadisst_time <- c("1967-01-16", "2018-12-16")
wc_hadisst_time <- c("1976-01-16","2018-12-16")
ebs_hadisst_time <- c("1981-01-16","2018-12-16")

oisst <- "ncdcOisst2Agg_LonPM180"
# split up into decades for easier downloading
oisst_time1 <- c("1982-01-01","1989-12-31") # same time interval for all regions
oisst_time2 <- c("1990-01-01","1999-12-31") 
oisst_time3 <- c("2000-01-01","2009-12-31") 
oisst_time4 <- c("2010-01-01","2018-12-31") 

oisst_fields <- "sst"

# get gridded datasets from ERDDAP
neus_hadisst_grid <- griddap(hadisst, time=neus_hadisst_time, latitude = neus_latrange, longitude = neus_lonrange, fields=hadisst_fields)
wc_hadisst_grid <- griddap(hadisst, time=wc_hadisst_time, latitude = wc_latrange, longitude = wc_lonrange, fields=hadisst_fields)
ebs_hadisst_grid <- griddap(hadisst, time=ebs_hadisst_time, latitude = ebs_latrange, longitude = ebs_lonrange, fields=hadisst_fields)

neus_oisst_grid1 <- griddap(oisst, time=oisst_time1, latitude = neus_latrange, longitude = neus_lonrange, fields=oisst_fields)
neus_oisst_grid2 <- griddap(oisst, time=oisst_time2, latitude = neus_latrange, longitude = neus_lonrange, fields=oisst_fields)
neus_oisst_grid3 <- griddap(oisst, time=oisst_time3, latitude = neus_latrange, longitude = neus_lonrange, fields=oisst_fields)
neus_oisst_grid4 <- griddap(oisst, time=oisst_time4, latitude = neus_latrange, longitude = neus_lonrange, fields=oisst_fields)

wc_oisst_grid1 <- griddap(oisst, time=oisst_time1, latitude = wc_latrange, longitude = wc_lonrange, fields=oisst_fields)
wc_oisst_grid2 <- griddap(oisst, time=oisst_time2, latitude = wc_latrange, longitude = wc_lonrange, fields=oisst_fields)
wc_oisst_grid3 <- griddap(oisst, time=oisst_time3, latitude = wc_latrange, longitude = wc_lonrange, fields=oisst_fields)
wc_oisst_grid4 <- griddap(oisst, time=oisst_time4, latitude = wc_latrange, longitude = wc_lonrange, fields=oisst_fields)

ebs_oisst_grid1 <- griddap(oisst, time=oisst_time1, latitude = ebs_latrange, longitude = ebs_lonrange, fields=oisst_fields)
ebs_oisst_grid2 <- griddap(oisst, time=oisst_time2, latitude = ebs_latrange, longitude = ebs_lonrange, fields=oisst_fields)
ebs_oisst_grid3 <- griddap(oisst, time=oisst_time3, latitude = ebs_latrange, longitude = ebs_lonrange, fields=oisst_fields)
ebs_oisst_grid4 <- griddap(oisst, time=oisst_time4, latitude = ebs_latrange, longitude = ebs_lonrange, fields=oisst_fields)

#####################
### resample HadISST to same spatial resolution as OISST
#####################

# find file paths to .nc files
neus_hadisst_nc_file <- neus_hadisst_grid$summary$filename
wc_hadisst_nc_file <- wc_hadisst_grid$summary$filename
ebs_hadisst_nc_file <- ebs_hadisst_grid$summary$filename

neus_oisst_nc_file1 <- neus_oisst_grid1$summary$filename
wc_oisst_nc_file1 <- wc_oisst_grid1$summary$filename
ebs_oisst_nc_file1 <- ebs_oisst_grid1$summary$filename

neus_oisst_nc_file2 <- neus_oisst_grid2$summary$filename
wc_oisst_nc_file2 <- wc_oisst_grid2$summary$filename
ebs_oisst_nc_file2 <- ebs_oisst_grid2$summary$filename

neus_oisst_nc_file3 <- neus_oisst_grid3$summary$filename
wc_oisst_nc_file3 <- wc_oisst_grid3$summary$filename
ebs_oisst_nc_file3 <- ebs_oisst_grid3$summary$filename

neus_oisst_nc_file4 <- neus_oisst_grid4$summary$filename
wc_oisst_nc_file4 <- wc_oisst_grid4$summary$filename
ebs_oisst_nc_file4 <- ebs_oisst_grid4$summary$filename

# read .nc files in as raster bricks

neus_hadisst_brick <- brick(neus_hadisst_nc_file)
wc_hadisst_brick <- brick(wc_hadisst_nc_file)
ebs_hadisst_brick <- brick(ebs_hadisst_nc_file)

neus_oisst_brick1 <- brick(neus_oisst_nc_file1)
neus_oisst_brick2 <- brick(neus_oisst_nc_file2)
neus_oisst_brick3 <- brick(neus_oisst_nc_file3)
neus_oisst_brick4 <- brick(neus_oisst_nc_file4)

wc_oisst_brick1 <- brick(wc_oisst_nc_file1)
wc_oisst_brick2 <- brick(wc_oisst_nc_file2)
wc_oisst_brick3 <- brick(wc_oisst_nc_file3)
wc_oisst_brick4 <- brick(wc_oisst_nc_file4)

ebs_oisst_brick1 <- brick(ebs_oisst_nc_file1)
ebs_oisst_brick2 <- brick(ebs_oisst_nc_file2)
ebs_oisst_brick3 <- brick(ebs_oisst_nc_file3)
ebs_oisst_brick4 <- brick(ebs_oisst_nc_file4)

# resample hadISST to resolution of OISST
neus_hadisst_resample <- resample(neus_hadisst_brick, neus_oisst_brick1, method="ngb") # nearest neighbor method does no interpolation and instead just pastes the value of the nearest point from the coarser raster 
wc_hadisst_resample <- resample(wc_hadisst_brick, wc_oisst_brick1, method="ngb")
ebs_hadisst_resample <- resample(ebs_hadisst_brick, ebs_oisst_brick1, method="ngb")

#####################
### create bathymetric masks for cropping SST data
#####################

# these take hours to generate so don't re-create them unless settings have changed or it's the first time! 
neus.bathy.file <- here("processed-data","neus_bathy_mask.shp")
wc.bathy.file <- here("processed-data","wc_bathy_mask.shp")
ebs.bathy.file <- here("processed-data","ebs_bathy_mask.shp")

# choose how far out into the ocean you want temperature data
ebs.depth.cutoff <- 300
neus.depth.cutoff <- 300
wc.depth.cutoff <- 600 # WC shelf is very steep so I increased this from 300m in 100m increments until the bathymetric mask did not have big gaps along the coast 

# get masks for each region; same bounding boxes as SST data above. using 4-minute resolution (default)
wc.bathy <- get.bathy(lon = wc_lonrange, lat = wc_latrange, visualize = F, res = 4) 
neus.bathy <- get.bathy(lon = neus_lonrange, lat = neus_latrange, visualize = F, res = 4) 
ebs.bathy <- get.bathy(lon = ebs_lonrange, lat = ebs_latrange, visualize = F, res = 4) 

# get CRS for future reference
bathy.crs <- wc.bathy %>% # works for all regions 
  as("SpatialPolygonsDataFrame") %>% 
  st_as_sf() %>% 
  st_crs() 

# get shapefile of the US EEZ, reproject to match bathymetry 
eezs <- st_read(here("raw-data/World_EEZ_v10_20180221","eez_v10.shp")) # download from http://www.marineregions.org/downloads.php and move to raw-data folder
useez <- eezs %>% 
  dplyr::filter(Sovereign1 == "United States") %>% 
  st_transform(crs=bathy.crs) 

# get bathymetric masks; slow 
if(!file.exists(wc.bathy.file)) {
  wc.bathy.mask <- wc.bathy %>% 
    as("SpatialPolygonsDataFrame") %>% 
    st_as_sf() %>% # retains CRS 
    dplyr::filter(layer <= wc.depth.cutoff) %>% # get rid of points over X m deep
    st_intersection(st_union(useez)) %>% # keep only points within the EEZ; crop out lakes, Canada 
    st_union() # merge polygons into one 
  # plot(wc.bathy.mask)
  
  st_write(wc.bathy.mask, wc.bathy.file) }else {
    wc.bathy.mask <- st_read(wc.bathy.file)
  }

if(!file.exists(ebs.bathy.file)) {
  ebs.bathy.mask <- ebs.bathy %>% 
    as("SpatialPolygonsDataFrame") %>% 
    st_as_sf() %>%
    dplyr::filter(layer <= ebs.depth.cutoff) %>% 
    st_intersection(st_union(useez)) %>%
    st_union()
  # plot(ebs.bathy.mask) 
  st_write(ebs.bathy.mask, ebs.bathy.file) }else {
    ebs.bathy.mask <- st_read(ebs.bathy.file)
  }

if(!file.exists(neus.bathy.file)) {
  neus.bathy.mask <- neus.bathy %>% 
    as("SpatialPolygonsDataFrame") %>% 
    st_as_sf() %>%
    dplyr::filter(layer <= neus.depth.cutoff) %>% 
    st_intersection(st_union(useez)) %>%
    st_union()
  st_write(neus.bathy.mask, neus.bathy.file) } else {
    neus.bathy.mask <- st_read(neus.bathy.file)
  }

#####################
### crop SST datasets to extent of masks 
#####################

# note that because HadISST is not downloaded with date in a date format (it's a character string), it ends up as the layer title rather than the @z dimension; let's fix that here 

neus_hadisst_times <- names(neus_hadisst_resample) %>%
  str_remove("X") %>%
  as.integer() %>%
  as_datetime()

wc_hadisst_times <- names(wc_hadisst_resample) %>%
  str_remove("X") %>%
  as.integer() %>%
  as_datetime()

ebs_hadisst_times <- names(ebs_hadisst_resample) %>%
  str_remove("X") %>%
  as.integer() %>%
  as_datetime()

neus_hadisst_crop <- mask(neus_hadisst_resample, as_Spatial(neus.bathy.mask)) 
neus_oisst_crop1 <- mask(neus_oisst_brick1, as_Spatial(neus.bathy.mask))
neus_oisst_crop2 <- mask(neus_oisst_brick2, as_Spatial(neus.bathy.mask))
neus_oisst_crop3 <- mask(neus_oisst_brick3, as_Spatial(neus.bathy.mask))
neus_oisst_crop4 <- mask(neus_oisst_brick4, as_Spatial(neus.bathy.mask))

wc_hadisst_crop <- mask(wc_hadisst_resample, as_Spatial(wc.bathy.mask))%>%
  setZ(z=wc_hadisst_times, name="time")
wc_oisst_crop1 <- mask(wc_oisst_brick1, as_Spatial(wc.bathy.mask))
wc_oisst_crop2 <- mask(wc_oisst_brick2, as_Spatial(wc.bathy.mask))
wc_oisst_crop3 <- mask(wc_oisst_brick3, as_Spatial(wc.bathy.mask))
wc_oisst_crop4 <- mask(wc_oisst_brick4, as_Spatial(wc.bathy.mask))

ebs_hadisst_crop <- mask(ebs_hadisst_resample, as_Spatial(ebs.bathy.mask))%>%
  setZ(z=ebs_hadisst_times, name="time")
ebs_oisst_crop1 <- mask(ebs_oisst_brick1, as_Spatial(ebs.bathy.mask))
ebs_oisst_crop2 <- mask(ebs_oisst_brick2, as_Spatial(ebs.bathy.mask))
ebs_oisst_crop3 <- mask(ebs_oisst_brick3, as_Spatial(ebs.bathy.mask))
ebs_oisst_crop4 <- mask(ebs_oisst_brick4, as_Spatial(ebs.bathy.mask))

# HadISST does have dates in the @z dimension, but for some reason they get dropped in resample() (maybe because they're in character format?). let's fix that now, by setting the @z dimension of the final cropped object to the dates from the original file: 
neus_hadisst_crop <- setZ(x=neus_hadisst_crop, z=as_datetime(unlist(neus_hadisst_brick@z)))
wc_hadisst_crop <- setZ(x=wc_hadisst_crop, z=as_datetime(unlist(wc_hadisst_brick@z)))
ebs_hadisst_crop <- setZ(x=ebs_hadisst_crop, z=as_datetime(unlist(ebs_hadisst_brick@z)))

#####################
### convert rasters to tidy dataframes and save  
#####################

# convert to dataframe, fix column names, and make date into date format 
neus_hadisst_df <- tabularaster::as_tibble(neus_hadisst_crop, cell=FALSE, dim=TRUE, values=TRUE, xy=TRUE) %>% 
  filter(!is.na(cellvalue))%>%
  rename("sst" = cellvalue,
         "date" = dimindex)%>% 
  mutate(date = as_date(date))
wc_hadisst_df <- tabularaster::as_tibble(wc_hadisst_crop, cell=FALSE, dim=TRUE, values=TRUE, xy=TRUE) %>% 
  filter(!is.na(cellvalue))%>%
  rename("sst" = cellvalue,
         "date" = dimindex)%>%
  mutate(date = as_date(date))
ebs_hadisst_df <- tabularaster::as_tibble(ebs_hadisst_crop, cell=FALSE, dim=TRUE, values=TRUE, xy=TRUE) %>% 
  filter(!is.na(cellvalue))%>%
  rename("sst" = cellvalue,
         "date" = dimindex) %>%
  mutate(date = as_date(date))

# fewer issues with OISST dates, can just convert them to date format here 

# convert all the OISST bricks to data frames 

# make function that takes cropped OISST raster brick and converts it to a dataframe using tabularaster, with some tidying 
oisst_to_df <- function(oisst){
  out <- tabularaster::as_tibble(oisst, cell=FALSE, dim=TRUE, values=TRUE, xy=TRUE) %>% 
    filter(!is.na(cellvalue)) %>%
    mutate(dimindex = as_datetime(as.integer(dimindex))) %>%
    rename("sst" = cellvalue,
           "date" = dimindex)
  return(out)
}

# get a list of all the rasters 
oisst_crop_list <- c(neus_oisst_crop1,neus_oisst_crop2,neus_oisst_crop3,neus_oisst_crop4,wc_oisst_crop1,wc_oisst_crop2,wc_oisst_crop3,wc_oisst_crop4,ebs_oisst_crop1,ebs_oisst_crop2,ebs_oisst_crop3,ebs_oisst_crop4)

# apply oisst_to_df to all rasters
oisst_df_list <- map(oisst_crop_list, oisst_to_df)

# give them sensible names 
names(oisst_df_list) <- c("neus_oisst_df1","neus_oisst_df2","neus_oisst_df3","neus_oisst_df4","wc_oisst_df1","wc_oisst_df2","wc_oisst_df3","wc_oisst_df4","ebs_oisst_df1","ebs_oisst_df2","ebs_oisst_df3","ebs_oisst_df4")

# unlist dfs into environment 
list2env(oisst_df_list, .GlobalEnv)

# make summary OISST dfs
neus_oisst_df <- bind_rows(neus_oisst_df1, neus_oisst_df2, neus_oisst_df3, neus_oisst_df4)
wc_oisst_df <- bind_rows(wc_oisst_df1, wc_oisst_df2, wc_oisst_df3, wc_oisst_df4)
ebs_oisst_df <- bind_rows(ebs_oisst_df1, ebs_oisst_df2, ebs_oisst_df3, ebs_oisst_df4)

# save all dfs
saveRDS(neus_hadisst_df, here("processed-data","neus_hadisst_df.rds"))
saveRDS(neus_oisst_df, here("processed-data","neus_oisst_df.rds"))
saveRDS(wc_hadisst_df, here("processed-data","wc_hadisst_df.rds"))
saveRDS(wc_oisst_df, here("processed-data","wc_oisst_df.rds"))
saveRDS(ebs_hadisst_df, here("processed-data","ebs_hadisst_df.rds"))
saveRDS(ebs_oisst_df, here("processed-data","ebs_oisst_df.rds"))
rm(list=ls())