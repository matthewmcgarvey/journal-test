package api

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

func NewRouter() *gin.Engine {
	r := gin.Default()

	r.GET("/healthz", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	})

	v1 := r.Group("/api/v1")
	{
		v1.GET("/accounts", func(c *gin.Context) {
			c.JSON(http.StatusOK, gin.H{"accounts": []any{}})
		})
		v1.GET("/accounts/:id", func(c *gin.Context) {
			c.JSON(http.StatusOK, gin.H{"account": gin.H{"id": c.Param("id")}})
		})
		v1.POST("/accounts", func(c *gin.Context) {
			c.JSON(http.StatusCreated, gin.H{"account": gin.H{"status": "created"}})
		})

		v1.GET("/transfers", func(c *gin.Context) {
			c.JSON(http.StatusOK, gin.H{"transfers": []any{}})
		})
		v1.GET("/transfers/:id", func(c *gin.Context) {
			c.JSON(http.StatusOK, gin.H{"transfer": gin.H{"id": c.Param("id")}})
		})
		v1.POST("/transfers", func(c *gin.Context) {
			c.JSON(http.StatusCreated, gin.H{"transfer": gin.H{"status": "created"}})
		})

		v1.GET("/account_balances", func(c *gin.Context) {
			c.JSON(http.StatusOK, gin.H{"balances": []any{}})
		})
	}

	return r
}
