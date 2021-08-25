# ENVIRONMENT ====

rm(list = ls())
library(tidyverse)
library(data.table)
library(googledrive)
library(readxl)
library(RColorBrewer)
library(lubridate)
library(boot)
library(e1071)
library(ggthemes)
library(gridExtra)
library(latex2exp)
library(Hmisc)

source('0-functions.r')

load('../data/emp_data.Rdata')
t_emp = emp_sum$t

# FIXED PARAMETERS
tgood = 2.6

pnullhat = 0.0
shapehat = 1/2
nulldf = 100
sigmahat = 1

Pr_tgood_yz = 0.15

# estimate bias adjustments
bias_exp = estimate_exponential(t_emp,tgood)
bias_mix = estimate_mixture(t_emp,tgood,pnullhat,shapehat,sigmahat)

# output to console
bias_exp %>% t()
bias_mix %>% t()

# simulate to plot dist
# eventually: just plot the pdf
nsim = 1e6
datmix = simmix(nsim,pnullhat,shapehat,bias_mix$scalehat,sigmahat)
datexp = simmix(nsim,pnull=0,shape=1,bias_exp$scalehat,sigmahat)


# PLOT EXP FIT ====
edge = seq(0,10,0.25)

## create data frame with all groups
t_exp = datexp$t
t_mix = datmix$t

datall = data.frame(t = t_emp, group = 'emp') %>% 
  rbind(
    data.frame(t = t_exp, group = 'exp')
  ) %>% 
  rbind(
    data.frame(t = t_mix, group = 'mix')
  )


hall = datall %>% 
  filter(t>min(edge), t<max(edge)) %>% 
  group_by(group) %>% 
  summarise(
    tmid = hist(t,edge)$mid
    , density = hist(t,edge)$density
  ) %>% 
  left_join(
    datall %>% group_by(group) %>% summarise(Pr_good = sum(t>tgood)/n())
  ) %>% 
  mutate(
    density_good = density/Pr_good
  )


custom_plot = function(dat, ylimnum){
  ggplot(
    dat
    , aes(x=tmid, y=density_good)
  ) +
    geom_line(
      aes(color = "Model")
      , linetype = "solid", size = 1.5
    ) +
    geom_bar(
      data = hall %>% filter(group=='emp')
      , aes(fill = "Data")
      , stat = 'identity', alpha = 0.6,
    ) +
    coord_cartesian(
      xlim = c(0, 10)
      , ylim = ylimnum
    ) +
    theme_economist_white(gray_bg = FALSE) +
    theme(
      axis.title = element_text(size = 12)
      , axis.text = element_text(size = 10)      
      , legend.title = element_text(size = 10)
      , legend.text = element_text(size = 10)
      , legend.key.size = unit(0.1, 'cm')
      , legend.position = c(70,80)/100
      , legend.key.width = unit(1,'cm')    
      , legend.spacing.y = unit(0.000001, 'cm')
      , legend.background = element_rect(colour = 'black', fill = 'white')
    ) +
    labs(
      x = TeX('t-stat magnitude |t|')
      , y = TeX('Density')
    ) +
    scale_x_continuous(breaks = 0:10) +
    scale_fill_manual(
      name = NULL,
      guide = "legend",
      values = c("Data" = 'gray30')
    ) +
    scale_color_manual(
      name = NULL,
      guide = "legend",
      values = c("Model" = niceblue)
    )
} # end custom_plot

## plot and save
p_fit = custom_plot(
  hall %>% filter(group == 'exp')
  , ylimnum = c(0,1.5)
)

p_fit

ggsave(p_fit, filename = '../results/fitexp.pdf', width = 5, height = 4)

# PLOT MIX VS DATA ====
edge = seq(0,10,0.25)

## create data frame with all groups
t_exp = datexp$t
t_mix = datmix$t

datall = data.frame(t = t_emp, group = 'emp') %>% 
  rbind(
    data.frame(t = t_exp, group = 'exp')
  ) %>% 
  rbind(
    data.frame(t = t_mix, group = 'mix')
  )

hall = datall %>% 
  filter(t>min(edge), t<max(edge)) %>% 
  group_by(group) %>% 
  summarise(
    tmid = hist(t,edge)$mid
    , density = hist(t,edge)$density
  ) %>% 
  left_join(
    datall %>% group_by(group) %>% summarise(Pr_good = sum(t>tgood)/n())
  ) %>% 
  mutate(
    density_good = density/Pr_good
  )

## plot and save
p_fit = custom_plot(
  hall %>% filter(group == 'mix')
  , ylimnum = c(0,10)
) 

p_fit

ggsave(p_fit, filename = '../results/fitmix.pdf', width = 5, height = 4)



# PLOT FDR ====

# settings
tbarlist = quantile(t_emp, seq(0.1,0.9,0.1))

# fdr calculations
tbarlist = seq(0,6,0.1) 

fdr_exp = estimate_fdr_parametric(
  pnull =  0, shape = 1, bias_exp$scalehat
  , tbarlist = tbarlist,nulldf = nulldf
) %>%
  transmute(tbar, fdr_exp = fdrhat)

fdr_mix = estimate_fdr_parametric(
  pnull =  pnullhat, shape = shapehat, bias_mix$scalehat
  , tbarlist = tbarlist,nulldf = nulldf
) %>%
  transmute(tbar, fdr_mix = fdrhat)

# YZ for comparison
fdr_yz = estimate_fdr(
  t_emp, tbarlist = tbarlist, C = 1/Pr_tgood_yz
) %>% 
  transmute(tbar, dr, fdr_yz = fdrhat) %>% 
  mutate(
     fdr_yz = if_else(tbar >= tgood, fdr_yz, NA_real_)
  )
  


fdr = fdr_exp %>% 
  left_join(
    fdr_mix, by = 'tbar'
  ) %>% 
  left_join(
    fdr_yz, by = 'tbar'
  ) %>% 
  mutate_at(
    .vars = vars(c(-tbar))
    , .funs = ~round(.*100,1)
  ) 



# prep plot
plotme = fdr %>% 
  select(-dr) %>% 
  pivot_longer(-tbar, names_to = 'type', values_to = 'fdr') %>% 
  mutate(
    type = factor(
      type
      , levels = c('fdr_exp','fdr_mix','fdr_yz')
      , labels = c('Exponential','Conservative','Non-Parametric')
    )
  )


# plot
legtitle = 'Publication Bias Adjustment'
ggplot(
  plotme
  , aes(x=tbar, y=fdr, group = type)
)   +
  geom_vline(xintercept = tgood, color = nicered) +
  geom_line(aes(linetype=type, color = type), size=2.5) +
  scale_linetype_manual(values=c("solid", "21", "41")) +
  scale_color_manual(values=c(niceblue, nicegreen, 'gray')) +
  theme_economist_white(gray_bg = FALSE) +
  theme(
    axis.title = element_text(size = 20)
    , axis.text = element_text(size = 14)      
    , legend.title = element_blank()
    , legend.text = element_text(size = 14)
    , legend.background = element_rect(colour = 'black', fill = 'white', linetype = 'solid')
  )  +
  labs(
    x = TeX('\\bar{t}')
    , y = TeX('FDR Upper Bound for $|t_i|>\\bar{t}$ (\\%)')
    , linetype = legtitle, color = legtitle
  )  +
  theme(
    legend.position = c(80,60)/100
    , legend.key.width = unit(3,'cm')
  ) +
  scale_x_continuous(breaks = seq(1,6,0.5)) +
  coord_cartesian(
    ylim = c(0,100)
    , xlim = c(1.5,4)
  ) + 
  annotate(
    'text', x=2.90, y=95
    , 'label' = TeX('\\bar{t}=\\hat{t}_{good}=2.60')
    , size = 5, color = nicered
  )

pdfscale = 0.7
ggsave('../results/emp-fdr.pdf', width = 10*pdfscale, height = 8*pdfscale)

# TABLE ====
texme_tlist = seq(1.6,4.0,0.2)

texme = 
  fdr %>%
  filter(
    tbar %in% texme_tlist
  ) %>% 
  mutate(
    blank = numeric(length(texme_tlist))*NA
  ) %>% 
  transmute(
    tbar = tbar
    , dr = dr
    , blank
    , fdr_exp    
    , fdr_mix
    , fdr_yz    
  ) 



# Produces latex table code
temp = latex(
  texme
  , file = '../results/tab-emp.tex'
  , table.env = F
  , first.hline.double = FALSE
  , rowname=NULL
  , na.blank = T
  , already.math.col.names = T
  , cdec = c(2,1, 1,1,1)
)



texme %>% print