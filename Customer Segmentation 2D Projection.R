# CUSTOMER SEGMENTATION ----


library(tidyverse)
library(broom)
library(umap)
library(ggrepel)
library(tidyquant)

bike_orderlines_tbl <- read_rds("C:/Users/romio/OneDrive/Desktop/Business_Analysis/00_data/bike_sales/data_wrangled/bike_orderlines.rds")

glimpse(bike_orderlines_tbl)


# 1.0 CUSTOMER TRENDS ----
# - GOAL: Mine Customer Purchase History for similarity to other "like" customers
# - TECHNIQUES: K-Means Clustering, UMAP 2D Projection

# 1.1 Get Customer Trends ----

customer_trends_tbl <- bike_orderlines_tbl %>% 
    
    select(bikeshop_name, price, model, category_1, category_2, frame_material, quantity) %>% 
    
    # Summarization and group by
    group_by(bikeshop_name, price, model, category_1, category_2, frame_material) %>% 
    summarise(quantity_purchased = sum(quantity)) %>% 
    ungroup() %>% 
    
    # Proportion 
    group_by(bikeshop_name) %>% 
    mutate(prop_of_total = quantity_purchased / sum(quantity_purchased)) %>% 
    ungroup() 

customer_trends_tbl

# 1.2 Convert to User-Item Format ----

customer_product_tbl <- customer_trends_tbl %>% 
    select(bikeshop_name, model, prop_of_total) %>% 
    
    spread(model, prop_of_total, fill = 0)

# 2.0 MODELING: K-MEANS CLUSTERING ----

# 2.1 Performing K-Means ----

kmeans_obj <- customer_product_tbl %>% 
    select(-bikeshop_name) %>% 
    kmeans(centers = 5, nstart = 100)

# 2.2 Tidying a K-Means Object ----

broom::tidy(kmeans_obj) %>% glimpse()

broom::glance(kmeans_obj)

broom::augment(kmeans_obj, data = customer_product_tbl) %>%
    select(bikeshop_name, .cluster)


# 2.3 How many centers (customer groups) to use? ----

# Functions that works on one element
kmeans_mapper <- function(centers = 3) {
    
    customer_product_tbl %>% 
        select(-bikeshop_name) %>% 
        kmeans(centers = centers, nstart = 100)
}

# Mapping the function to many elements

kmeans_mapped_tbl <- tibble(centers = 1:15) %>% 
    mutate(k_means = centers %>% map(kmeans_mapper)) %>% 
    mutate(glance = k_means %>% map(glance))

kmeans_mapped_tbl %>% 
    unnest(glance) %>% 
    select(centers, tot.withinss)

# 2.4 Skree Plot ----

# Visualization
kmeans_mapped_tbl %>% 
    unnest(glance) %>% 
    select(centers, tot.withinss) %>% 
    ggplot(aes(centers, tot.withinss)) +
    geom_point(colour = '#2c3e50', size = 4) +
    geom_line(colour = '#2c3e50', linewidth = 1) +
    ggrepel::geom_label_repel(aes(label = centers), color = '#2c3e50') +
    
    # Formatting
    theme_tq() +
    labs(
        title = "Skree Plot",
        subtitle = "Measures the distance each of the customer are from the closes K-Means center",
        caption = "Conclusion: Based on the Scree Plot, we select 4 clusters to segment the customer base."
    )


# 3.0 VISUALIZATION: UMAP ----

# 3.1 Use UMAP to get 2-D Projection ----

umap_obj <- customer_product_tbl %>% 
    select(-bikeshop_name) %>% 
    umap()

umap_results_tbl <- umap_obj$layout %>% as_tibble() %>% 
    set_names(c('x', 'y')) %>% 
    bind_cols(
        customer_product_tbl %>% select(bikeshop_name)
    )

umap_results_tbl %>% 
    ggplot(aes(x, y)) +
    geom_point(size = 2, color = "#2c3e50") +
    geom_label_repel(aes(label = bikeshop_name))

# 3.2 Use K-Means to Add Cluster Assignments ----

kmeans_4_obj <- kmeans_mapped_tbl %>% 
    pull(k_means) %>% 
    pluck(4)

kmeans_4_clusters_tbl <- kmeans_4_obj %>% augment(customer_product_tbl) %>% 
    select(bikeshop_name, .cluster)

umap_kmeans_4_results_tbl <- umap_results_tbl %>% 
    left_join(kmeans_4_clusters_tbl)

# 3.3 Visualize UMAP'ed Projections with Cluster Assignments ----

umap_kmeans_4_results_tbl %>% 
    mutate(
        label_text = str_glue("{bikeshop_name}
                              {.cluster}"
        )) %>% 
    ggplot(aes(x, y, colour = .cluster)) + 
    geom_point() +
    geom_label_repel(aes(label = label_text)) +
    # Geometries
    
    
    # Formatting
    theme_tq() +
    scale_color_tq() +
    labs(
        title = "Customer Segmentation: 2D Projection",
        subtitle = "UMAP 2D Projection with K-Means Cluster Assignment",
        caption = "Conclusion: 4 Customer Segments identified using 2 algorithms"
    ) +
    theme(legend.position = "none")


# 4.0 ANALYZE PURCHASING TRENDS ----

customer_trends_tbl$price %>% 
    quantile(c(0, 0.33, 0.66, 1))

# Join Cluster Assignment by Bikeshop Name

cluster_trends_tbl <- customer_trends_tbl %>% 
    left_join(kmeans_4_clusters_tbl) %>% 
    mutate(price_bins = case_when(
        price <= 2240 ~ "Low",
        price <= 4260 ~ "Medium",
        TRUE~ "High"
    )) %>% 
    select(.cluster, model, contains('price'),
           category_1:quantity_purchased) %>% 
    
    
    # Aggregate quantity purchased by cluster and product attributes
    
    group_by_at(.vars = vars(.cluster:frame_material)) %>% 
    summarise(total_quantity = sum(quantity_purchased)) %>% 
    ungroup() %>% 
    
    
    # Calculate Proportion of Total
    group_by(.cluster) %>% 
    mutate(prop_of_total = total_quantity / sum(total_quantity)) 

cluster_trends_tbl


# Cluster 1 - Low/Medium Price, Road Model Preference

get_cluster_trends <- function(cluster) {
    
    cluster_trends_tbl %>% 
        filter(.cluster == cluster) %>% 
        arrange(desc(prop_of_total)) %>% 
        mutate(cum_sum = CUMULATIVE_SUM(prop_of_total))
}



# Cluster 2 - Low/Medium Price, Mountain Model Preference, Aluminum Frame

2 %>% get_cluster_trends()

# Cluster 3 - High End Price, Mountain Preference, Carbon Frame
3 %>% get_cluster_trends()

# Cluster 4 - High End Price, Road Preference, Carbon Frame
4 %>% get_cluster_trends()

# Update Visualization

cluster_label_tbl <- tibble(
    .cluster = as.character(1:4),
    .cluster_label = c('Low/Medium Price, Road',
                       'Low/Medium Price, Mountain, Aluminum',
                       'High End Price, Mountain, Carbon',
                       'High End Price, Road, Carbon'
    )
    
)

umap_kmeans_4_results_tbl %>% 
    left_join(cluster_label_tbl) %>% 
    mutate(
        label_text = str_glue("{bikeshop_name}
                              {.cluster}
                              {.cluster_label}"
        )) %>% 
    ggplot(aes(x, y, colour = .cluster)) + 
    geom_point() +
    geom_label_repel(aes(label = label_text), size = 2.5) +
    # Geometries
    
    
    # Formatting
    theme_tq() +
    scale_color_tq() +
    labs(
        title = "Customer Segmentation: 2D Projection",
        subtitle = "UMAP 2D Projection with K-Means Cluster Assignment",
        caption = "Conclusion: 4 Customer Segments identified using 2 algorithms"
    ) +
    theme(legend.position = "none")





