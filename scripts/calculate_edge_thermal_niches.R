#######################
### load packages 
#######################

library(data.table)
library(tidyverse)
library(here)
library(purrr)
library(broom)
library(lmerTest)
library(mgcv)
library(rstanarm)
library(tidybayes)
#library(pwr)

#######################
### load data 
#######################

# DON'T FORGET TO RE-RUN VALIDATE_EDGE_SPP AFTER RE-RUNNING VAST!
dat.models <- readRDS(here("processed-data","all_edge_spp_df.rds")) %>%
  ungroup() %>% # undo rowwise nature
  mutate(axis = as.character(axis)) %>% # convert from factor
  filter(axis %in% c('coast_km','line_km')) 

# how many species?

dat.summary <- dat.models %>% 
  group_by(species, quantile, region) %>%
  summarise() %>% 
  ungroup() %>%
  mutate(species=str_to_sentence(species),
         region=recode(region,
                       ebs="Eastern Bering Sea",
                       neus="Northeast",
                       wc="West Coast"),
         quantile=recode(quantile,
                         quantile_0.01="Warm Limit",
                         quantile_0.99="Cold Limit"))

dat.models.groups <- dat.models %>%
  select(species, edgetype, region, taxongroup) %>%
  distinct() %>%
  mutate(species = as.factor(species), 
         edgetype=as.factor(edgetype),
         region=as.factor(region),
         taxongroup=as.factor(taxongroup))

#######################
### species shifts vs time
#######################

spp.bayes.edge.lm.df <- NULL
for(i in unique(dat.models$species)) {
  dfprep1 <- dat.models[dat.models$species==i,] # subdivide by species 
  for(j in unique(dfprep1$region)) {
    dfprep2 <- dat.models[dat.models$species==i & dat.models$region==j,] # subdivide by region, for the few spp found in multiple regions 
    for(k in unique(dfprep2$quantile)) {
      df <- dat.models[dat.models$species==i & dat.models$region==j & dat.models$quantile==k,] # subdivide by quantile, for the few spp with both range edges
      spp.bayes.lm <- try(stan_glm(Estimate ~ year, 
                                   data=df, 
                                   family=gaussian(), 
                                   iter = 40000,
                                   warmup = 10000,
                                   adapt_delta = 0.99,
                                   chains = 4,
                                   cores = 1,
                                   prior = normal(0, 50),
                                   weights = 1/(Std.Error^2)
      )) # centered on 0 to allow negative coefficients for some species. SD of 50 intended to exceed upper range of marine climate velocities (around 200 km/dec) in Burrows et al 2011
      if(!class(spp.bayes.lm)[1] == "try-error") { # adding try() here because some edges are so invariant that the model fails 
        spp.bayes.lm.tidy <- tidy_draws(spp.bayes.lm) %>%
          mutate(species = paste0(i),
                 region = paste0(j),
                 quantile = paste0(k),
                 intercept.rhat = summary(spp.bayes.lm)[,"Rhat"][1],
                 year_match.rhat = summary(spp.bayes.lm)[,"Rhat"][2],
                 sigma.rhat = summary(spp.bayes.lm)[,"Rhat"][3])
        spp.bayes.edge.lm.df <- rbind(spp.bayes.edge.lm.df, spp.bayes.lm.tidy)
      }
    }
  }
}

# check for convergence 
quantile(spp.bayes.edge.lm.df$intercept.rhat)
quantile(spp.bayes.edge.lm.df$year_match.rhat)  
quantile(spp.bayes.edge.lm.df$sigma.rhat) # this previously caused estimation problems, doesn't appear to be doing that anymore  

spp.bayes.edge.filter <- spp.bayes.edge.lm.df %>% 
  group_by(region, species, quantile) %>%
  mutate(max.rhat = max(intercept.rhat, year_match.rhat, sigma.rhat)) %>%
  filter(max.rhat <= 1.1) # get rid of spp*region*edge combos where one of the edge ~ time models didn't converge--just a check--may not get rid of any 

setdiff(spp.bayes.edge.lm.df %>% select(region, species, quantile) %>% distinct(), spp.bayes.edge.filter %>% select(region, species, quantile) %>% distinct()) # 0 at present, all models converged

rm(spp.bayes.edge.filter) # if they all converged this is the same as spp.bayes.edge.lm.df

# plot posteriors 
# bayes.lm.time.gg <- spp.bayes.edge.lm.df  %>%
#   group_by(.draw, region) %>%
#   mutate(mean.param = mean(year) ) %>%
#   ungroup() %>%
#   select(.draw, mean.param, region) %>%
#   distinct() %>%
#   ggplot() +
#   theme_bw() +
#   geom_density(aes(x=mean.param, fill=region), color="black", alpha=0.5) +
#   scale_fill_brewer(type="seq", palette="YlGnBu", labels=c("Eastern Bering Sea","Northeast","West Coast")) +
#   labs(x="Coefficient of Edge Position on Time (km/yr)", y="Density", fill="Region") +
#   theme(legend.position="bottom") +
#   NULL
# bayes.lm.time.gg
# ggsave(bayes.lm.time.gg, width=3, height=4, dpi=160, filename=here("results","edge_coefficients_time.png"), scale=1.6)

bayes.lm.time.edgetype.gg <- spp.bayes.edge.lm.df  %>%
  group_by(.draw, region, quantile) %>%
  mutate(mean.param = mean(year) ) %>%
  ungroup() %>%
  select(.draw, mean.param, region, quantile) %>%
  distinct() %>%
  mutate(quantile=recode(quantile,
                         quantile_0.01="Equatorward Edge",
                         quantile_0.99="Poleward Edge"),
         region=factor(region, levels=c('neus','wc','ebs'))) %>%
  ggplot() +
  theme_bw() +
  geom_density(aes(x=mean.param, fill=region), color="black", alpha=0.5) +
  scale_fill_brewer(type="seq", palette="YlGnBu", labels=c("Northeast","West Coast","Eastern Bering Sea")) +
  labs(x="Coefficient of Edge Position on Time (km/yr)", y="Density", fill="Region") +
  theme(legend.position="bottom") +
  facet_wrap(~quantile) +
  NULL
bayes.lm.time.edgetype.gg
ggsave(bayes.lm.time.edgetype.gg, width=168, height=100,
       units="mm", dpi=600, filename=here("results","edge_coefficients_time_edgetype.png"))

# generate posteriors grouped different ways--need full model output for this 

# edge shift stats pooled by region
spp.bayes.edge.lm.df %>%
  group_by(.draw, region) %>%
  summarise(mean.year = mean(year)) %>%
  group_by(region) %>%
  summarise(mean=mean(mean.year),
            median=median(mean.year),
            lower=quantile(mean.year, 0.05),
            upper=quantile(mean.year, 0.95))


# edge shift stats pooled by edgetype
spp.bayes.edge.lm.df %>%
  group_by(.draw, quantile) %>%
  summarise(mean.year = mean(year)) %>%
  group_by(quantile) %>%
  summarise(mean=mean(mean.year),
            median=median(mean.year),
            lower=quantile(mean.year, 0.05),
            upper=quantile(mean.year, 0.95))

# edge shift stats pooled by region and edgetype
spp.bayes.edge.lm.df %>%
  group_by(.draw, region, quantile) %>%
  summarise(mean.year = mean(year)) %>%
  group_by(region, quantile) %>%
  summarise(mean=mean(mean.year),
            median=median(mean.year),
            lower=quantile(mean.year, 0.05),
            upper=quantile(mean.year, 0.95))

# edge shift stats pooled by taxon group 
spp.bayes.edge.lm.df %>%
  left_join(dat.models.groups) %>%
  group_by(.draw, taxongroup) %>%
  summarise(mean.year = mean(year)) %>%
  group_by(taxongroup) %>%
  summarise(mean=mean(mean.year),
            median=median(mean.year),
            lower=quantile(mean.year, 0.05),
            upper=quantile(mean.year, 0.95))

# pooled by taxon group and edge type
spp.bayes.edge.lm.df %>%
  left_join(dat.models.groups) %>%
  group_by(.draw, taxongroup, quantile) %>%
  summarise(mean.year = mean(year)) %>%
  group_by(taxongroup, quantile) %>%
  summarise(mean=mean(mean.year),
            median=median(mean.year),
            lower=quantile(mean.year, 0.05),
            upper=quantile(mean.year, 0.95))

# species-specific results
spp.bayes.edge.lm.df.summary <- spp.bayes.edge.lm.df %>%
  group_by(.draw, species, region, quantile) %>%
  summarise(mean.year = mean(year)) %>%
  group_by(species, region, quantile) %>%
  summarise(mean=mean(mean.year),
            median=median(mean.year),
            lower=quantile(mean.year, 0.05),
            upper=quantile(mean.year, 0.95))

write_csv(spp.bayes.edge.lm.df.summary, here("results","species_edge_shifts_vs_time.csv"))

#######################
### predict temperatures at edges 
#######################

# split by region because temp datasets are different

# set up temp data
ebs.sst <- readRDS(here("processed-data","ebs_sst_linedist.rds"))
wc.sst <- readRDS(here("processed-data","wc_sst_coastdist.rds"))
neus.sst <- readRDS(here("processed-data","neus_sst_coastdist.rds"))

ebs.sst.prepgam <- ebs.sst %>% 
  group_by(line_km, year_match) %>%
  mutate(sstmean = mean(sst),
         sstmax = max(sst),
         sstmin = min(sst)) %>%
  ungroup() %>%
  dplyr::select(year_match, line_km, sstmean, sstmax, sstmin) %>%
  distinct() %>%
  mutate(year_match = as.factor(year_match)) 

wc.sst.prepgam <- wc.sst %>% 
  group_by(coast_km, year_match) %>%
  mutate(sstmean = mean(sst),
         sstmax = max(sst),
         sstmin = min(sst)) %>%
  ungroup() %>%
  dplyr::select(year_match, coast_km, sstmean,sstmax, sstmin) %>%
  distinct() %>%
  mutate(year_match = as.factor(year_match)) 

neus.sst.prepgam <- neus.sst %>% 
  group_by(coast_km, year_match) %>%
  mutate(sstmean = mean(sst),
         sstmax = max(sst),
         sstmin = min(sst)) %>%
  ungroup() %>%
  dplyr::select(year_match, coast_km, sstmean,sstmax, sstmin) %>%
  distinct() %>%
  mutate(year_match = as.factor(year_match)) 

# set up GAMs for coastal and NW axes 
# note that the 99, 01 names aren't really appropriate anymore now that we are using monthly means
ebs.sst.temp.gam.mean <- gam(sstmean ~ year_match + s(line_km, by=year_match), data=ebs.sst.prepgam)
ebs.sst.temp.gam.99 <- gam(sstmax ~ year_match + s(line_km, by=year_match), data=ebs.sst.prepgam)
ebs.sst.temp.gam.01 <- gam(sstmin ~ year_match + s(line_km, by=year_match), data=ebs.sst.prepgam)

wc.sst.temp.gam.mean <- gam(sstmean ~ year_match + s(coast_km, by=year_match), data=wc.sst.prepgam)
wc.sst.temp.gam.99 <- gam(sstmax ~ year_match + s(coast_km, by=year_match), data=wc.sst.prepgam)
wc.sst.temp.gam.01 <- gam(sstmin ~ year_match + s(coast_km, by=year_match), data=wc.sst.prepgam)

neus.sst.temp.gam.mean <- gam(sstmean ~ year_match + s(coast_km, by=year_match), data=neus.sst.prepgam)
neus.sst.temp.gam.99 <- gam(sstmax ~ year_match + s(coast_km, by=year_match), data=neus.sst.prepgam)
neus.sst.temp.gam.01 <- gam(sstmin ~ year_match + s(coast_km, by=year_match), data=neus.sst.prepgam)

# predict temp from edge position--prep datasets

ebs.pred <- dat.models %>%
  filter(region=="ebs") %>%
  dplyr::select( -axis) %>%
  rename(line_km=Estimate,
         year_match=year) 

wc.pred <- dat.models %>%
  filter(region=="wc") %>%
  dplyr::select( -axis) %>%
  rename(coast_km=Estimate,
         year_match=year) 

neus.pred <- dat.models %>%
  filter(region=="neus") %>%
  dplyr::select( -axis) %>%
  rename(coast_km=Estimate,
         year_match=year) 

# add columns with predicted temperature at edge every year 
ebs.pred$predict.sstmean <- predict.gam(ebs.sst.temp.gam.mean, ebs.pred)
ebs.pred$predict.sstmean.se <- predict.gam(ebs.sst.temp.gam.mean, ebs.pred, se.fit=TRUE)$se.fit
ebs.pred$predict.sstmax <- predict.gam(ebs.sst.temp.gam.99, ebs.pred)
ebs.pred$predict.sstmax.se <- predict.gam(ebs.sst.temp.gam.99, ebs.pred,se.fit=TRUE)$se.fit
ebs.pred$predict.sstmin <- predict.gam(ebs.sst.temp.gam.01, ebs.pred)
ebs.pred$predict.sstmin.se <- predict.gam(ebs.sst.temp.gam.01, ebs.pred,se.fit=TRUE)$se.fit

wc.pred$predict.sstmean <- predict.gam(wc.sst.temp.gam.mean, wc.pred)
wc.pred$predict.sstmean.se <- predict.gam(wc.sst.temp.gam.mean, wc.pred, se.fit=TRUE)$se.fit
wc.pred$predict.sstmax <- predict.gam(wc.sst.temp.gam.99, wc.pred)
wc.pred$predict.sstmax.se <- predict.gam(wc.sst.temp.gam.99, wc.pred,se.fit=TRUE)$se.fit
wc.pred$predict.sstmin <- predict.gam(wc.sst.temp.gam.01, wc.pred)
wc.pred$predict.sstmin.se <- predict.gam(wc.sst.temp.gam.01, wc.pred, se.fit=TRUE)$se.fit

neus.pred$predict.sstmean <- predict.gam(neus.sst.temp.gam.mean, neus.pred)
neus.pred$predict.sstmean.se <- predict.gam(neus.sst.temp.gam.mean, neus.pred, se.fit=TRUE)$se.fit
neus.pred$predict.sstmax <- predict.gam(neus.sst.temp.gam.99, neus.pred)
neus.pred$predict.sstmax.se <- predict.gam(neus.sst.temp.gam.99, neus.pred, se.fit=TRUE)$se.fit
neus.pred$predict.sstmin <- predict.gam(neus.sst.temp.gam.01, neus.pred)
neus.pred$predict.sstmin.se <- predict.gam(neus.sst.temp.gam.01, neus.pred, se.fit=TRUE)$se.fit

neus.pred <- rename(neus.pred, edge_position=coast_km)
neus.pred$axis <- "coast_km"

wc.pred <- rename(wc.pred, edge_position=coast_km)
wc.pred$axis <- "coast_km"

ebs.pred <- rename(ebs.pred, edge_position=line_km)
ebs.pred$axis <- "line_km"

# tidy columns and combine
dat.predict1 <- rbind(neus.pred, wc.pred, ebs.pred)%>%
  select(-predict.sstmean.se, -predict.sstmax.se, -predict.sstmin.se) %>%
  pivot_longer(cols=c(predict.sstmean, predict.sstmax, predict.sstmin), names_to="predicted.var",values_to="sst") 

dat.predict <- rbind(neus.pred, wc.pred, ebs.pred)%>%
  select(-predict.sstmean, -predict.sstmax, -predict.sstmin) %>%
  pivot_longer(cols=c(predict.sstmean.se, predict.sstmax.se, predict.sstmin.se), names_to="predicted.var",values_to="sstSE") %>%
  mutate(predicted.var=str_replace(predicted.var, ".se","")) %>%
  inner_join(dat.predict1)

dat.predict.niche <- dat.predict %>%
  filter(!predicted.var=="predict.sstmean")
write_csv(dat.predict.niche, here("processed-data","species_thermal_niche_v_time.csv"))


#######################
### estimate change in edge thermal niche over time
#######################

# Bayesian test for edge thermal niche change over time 

spp.bayes.niche.lm.df <- NULL
for(i in unique(dat.predict.niche$species)) {
  dfprep1 <- dat.predict.niche[dat.predict.niche$species==i,] # subdivide by species 
  for(j in unique(dfprep1$region)) {
    dfprep2 <- dat.predict.niche[dat.predict.niche$species==i & dat.predict.niche$region==j,] # subdivide by region, for the few spp found in multiple regions 
    for(k in unique(dfprep2$quantile)) {
      dfprep3 <- dat.predict.niche[dat.predict.niche$species==i & dat.predict.niche$region==j & dat.predict.niche$quantile==k,] # subdivide by quantile, for the few spp with both range edges
      for(l in unique(dfprep3$predicted.var)){
        df <- dat.predict.niche[dat.predict.niche$species==i & dat.predict.niche$region==j & dat.predict.niche$quantile==k & dat.predict.niche$predicted.var==l,] # split by the two temperature extremes that we want to analyze separately
        spp.bayes.lm <- try(stan_glm(sst ~ year_match, 
                                     data=df, 
                                     family=gaussian(), 
                                     iter = 40000,
                                     warmup = 10000,
                                     adapt_delta = 0.99,
                                     chains = 4,
                                     cores = 1,
                                     prior = normal(0, 0.1), # exceeds highest rates of warming we found in the paper which were around 0.04 C/yr
                                     control = list(max_treedepth = 20),
                                     weights = 1/(sstSE^2)
        ))
        if(!class(spp.bayes.lm)[1] == "try-error") { # adding try() here because some edges are so invariant that the model fails 
          spp.bayes.lm.tidy <- tidy_draws(spp.bayes.lm) %>%
            mutate(species = paste0(i),
                   region = paste0(j),
                   quantile = paste0(k),
                   predicted.var = paste0(l),
                   intercept.rhat = summary(spp.bayes.lm)[,"Rhat"][1],
                   year_match.rhat = summary(spp.bayes.lm)[,"Rhat"][2],
                   sigma.rhat = summary(spp.bayes.lm)[,"Rhat"][3])
          spp.bayes.niche.lm.df <- rbind(spp.bayes.niche.lm.df, spp.bayes.lm.tidy)
        }
      }
    }
  }
}
quantile(spp.bayes.niche.lm.df$intercept.rhat)
quantile(spp.bayes.niche.lm.df$year_match.rhat)  
quantile(spp.bayes.niche.lm.df$sigma.rhat) # this previously caused estimation problems, doesn't appear to be doing that anymore  

spp.bayes.niche.filter <- spp.bayes.niche.lm.df %>% 
  group_by(region, species, quantile) %>%
  mutate(max.rhat = max(intercept.rhat, year_match.rhat, sigma.rhat)) %>%
  filter(max.rhat <= 1.1) # get rid of spp*region*edge combos where one of the SST extreme models didn't converge--just a check--may not get rid of any 

setdiff(spp.bayes.niche.lm.df %>% select(region, species, quantile) %>% distinct(), spp.bayes.niche.filter %>% select(region, species, quantile) %>% distinct()) # 0 at present 

# SLOW

# summarize posterior distributions and write out 
spp.bayes.niche.lm.stats <- spp.bayes.niche.filter %>% 
  group_by(.draw, species, region, quantile, predicted.var) %>%
  summarise(beta.mean = mean(year_match)) %>%
  group_by(species, region, quantile, predicted.var) %>%
  summarise(mean=mean(beta.mean),
            median=median(beta.mean),
            lower=quantile(beta.mean, 0.05),
            upper=quantile(beta.mean, 0.95)) %>%
  select(species, region, quantile, predicted.var, mean, median, lower, upper) %>%
  distinct()
write_csv(spp.bayes.niche.lm.stats, here("results","species_bayes_niche_lm_summary.csv"))

quantile(spp.bayes.niche.lm.stats$mean) # should be distributed in the neighborhood of zero
spp.bayes.niche.lm.stats %>% 
  ggplot() +
  geom_histogram(aes(x=mean))


##########################
# Figure 1 example plots
##########################

# while most plots are generated in figure-scripts, these require the full STAN output to generate posteriors 
# the other small plots in the methods figure are generated in the respective figure-scripts files (e.g., time-series of range edges are generated in figure-scripts/species_edges_vs_time.R)

# non tracker - lobster - neus 

# make example plots for methods schematic 
ex.spp.ebs <- "paralithodes camtschaticus" # red king crab
ex.spp.neus <- "gadus morhua" # atlantic cod
ex.spp.wc <- "sebastes pinniger" # canary rockfish

summary.spp.ebs <- spp.bayes.niche.lm.stats %>% 
  filter(species==ex.spp.ebs)

summary.spp.neus <- spp.bayes.niche.lm.stats %>% 
  filter(species==ex.spp.neus)

summary.spp.wc <- spp.bayes.niche.lm.stats %>% 
  filter(species==ex.spp.wc, region=="wc")

# if species are updated, be sure to change year limits in the time-series figures below 

ex.spp.bayes.gg.ebs <- spp.bayes.niche.filter %>%
  filter(species==ex.spp.ebs) %>%
  group_by(.draw, predicted.var) %>%
  mutate(mean.param = mean(year_match) ) %>%
  ungroup() %>%
  select(.draw, mean.param, predicted.var) %>%
  distinct() %>%
  ggplot() +
  theme_bw() +
  geom_density(aes(x=mean.param, fill=predicted.var), color="black", alpha=0.5) +
  geom_vline(aes(xintercept=0), color="black", linetype="dotted") + 
  geom_segment(aes(x=summary.spp.ebs[summary.spp.ebs$predicted.var=="predict.sstmax",]$lower, xend=summary.spp.ebs[summary.spp.ebs$predicted.var=="predict.sstmax",]$upper, y=-1, yend=-1), color="#DF2301", lwd=2) + # add 90% credible interval 
  geom_segment(aes(x=summary.spp.ebs[summary.spp.ebs$predicted.var=="predict.sstmin",]$lower, xend=summary.spp.ebs[summary.spp.ebs$predicted.var=="predict.sstmin",]$upper, y=0, yend=0), color="#3A4ED0", lwd=2) +
  scale_fill_manual(values=c("#DF2301","#3A4ED0"), labels=c("Warm Extreme","Cold Extreme")) +
  labs(x="Coefficient (°C/year)",y="Density", fill=NULL) +
  scale_x_continuous(breaks=c(-0.1, -0.05, 0, 0.05)) +
  theme(legend.position="none") +
  NULL
ex.spp.bayes.gg.ebs

ex.spp.bayes.gg.neus <- spp.bayes.niche.filter %>%
  filter(species==ex.spp.neus) %>%
  group_by(.draw, predicted.var) %>%
  mutate(mean.param = mean(year_match) ) %>%
  ungroup() %>%
  select(.draw, mean.param, predicted.var) %>%
  distinct() %>%
  ggplot() +
  theme_bw() +
  geom_density(aes(x=mean.param, fill=predicted.var), color="black", alpha=0.5) +
  geom_vline(aes(xintercept=0), color="black", linetype="dotted") + 
  geom_segment(aes(x=summary.spp.neus[summary.spp.neus$predicted.var=="predict.sstmax",]$lower, xend=summary.spp.neus[summary.spp.neus$predicted.var=="predict.sstmax",]$upper, y=-1, yend=-1), color="#DF2301", lwd=2) + # add 90% credible interval 
  geom_segment(aes(x=summary.spp.neus[summary.spp.neus$predicted.var=="predict.sstmin",]$lower, xend=summary.spp.neus[summary.spp.neus$predicted.var=="predict.sstmin",]$upper, y=0, yend=0), color="#3A4ED0", lwd=2) +scale_fill_manual(values=c("#DF2301","#3A4ED0"), labels=c("Warm Extreme","Cold Extreme")) +
  labs(x="Coefficient (°C/year)",y="Density", fill=NULL) +
  scale_x_continuous(breaks=c(-0.1, -0.05, 0, 0.05)) +
  theme(legend.position="none") +
  NULL
ex.spp.bayes.gg.neus

ex.spp.bayes.gg.wc <- spp.bayes.niche.filter %>%
  filter(species==ex.spp.wc) %>%
  group_by(.draw, predicted.var) %>%
  mutate(mean.param = mean(year_match) ) %>%
  ungroup() %>%
  select(.draw, mean.param, predicted.var) %>%
  distinct() %>%
  ggplot() +
  theme_bw() +
  geom_density(aes(x=mean.param, fill=predicted.var), color="black", alpha=0.5) +
  geom_vline(aes(xintercept=0), color="black", linetype="dotted") + 
  geom_segment(aes(x=summary.spp.wc[summary.spp.wc$predicted.var=="predict.sstmax",]$lower, xend=summary.spp.wc[summary.spp.wc$predicted.var=="predict.sstmax",]$upper, y=-1, yend=-1), color="#DF2301", lwd=2) + # add 90% credible interval 
  geom_segment(aes(x=summary.spp.wc[summary.spp.wc$predicted.var=="predict.sstmin",]$lower, xend=summary.spp.wc[summary.spp.wc$predicted.var=="predict.sstmin",]$upper, y=0, yend=0), color="#3A4ED0", lwd=2) +scale_fill_manual(values=c("#DF2301","#3A4ED0"), labels=c("Warm Extreme","Cold Extreme")) +
  labs(x="Coefficient (°C/year)",y="Density", fill=NULL) +
  scale_x_continuous(breaks=c(-0.1, -0.05, 0, 0.05)) +
  theme(legend.position="none") +
  NULL
ex.spp.bayes.gg.wc

ggsave(ex.spp.bayes.gg.ebs, dpi=600, width=1.5, height=1.4, filename=here("results",paste0("example_posterior_",ex.spp.ebs, ".png")),scale=1.5)
ggsave(ex.spp.bayes.gg.neus, dpi=600, width=1.5, height=1.4, filename=here("results",paste0("example_posterior_",ex.spp.neus,".png")),scale=1.5)
ggsave(ex.spp.bayes.gg.wc, dpi=600, width=1.5, height=1.4, filename=here("results",paste0("example_posterior_",ex.spp.wc,".png")),scale=1.5)
